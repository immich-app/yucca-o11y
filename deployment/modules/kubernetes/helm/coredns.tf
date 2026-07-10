# TF-seeded, not Flux-managed: Flux needs cluster DNS for external fetches AND for
# controller->controller artifact URLs, so a fresh bootstrap would deadlock if Flux
# installed it. Talos's CoreDNS is disabled in talos/cluster.
locals {
  # netbird-dns Service pin; published to Flux via bootstrap-settings.
  netbird_dns_ip = "10.96.0.53"
}

resource "helm_release" "coredns" {
  name            = "coredns"
  namespace       = "kube-system"
  repository      = "oci://ghcr.io/coredns/charts"
  chart           = "coredns"
  version         = var.coredns_version
  cleanup_on_fail = true
  # Adopts the same-named Talos coredns objects in place on a live cluster.
  take_ownership = true

  values = [<<-YAML
    fullnameOverride: coredns
    image:
      repository: mirror.gcr.io/coredns/coredns
    replicaCount: 2
    k8sAppLabelOverride: kube-dns
    priorityClassName: system-cluster-critical
    # Selectors pinned to the Talos originals: Deployment selectors are immutable, and an
    # identical Service selector makes adoption a plain rolling update (no empty endpoints).
    deployment:
      selector:
        matchLabels:
          k8s-app: kube-dns
    service:
      name: kube-dns
      clusterIP: 10.96.0.10
      selector:
        k8s-app: kube-dns
    tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
    affinity:
      podAntiAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              topologyKey: kubernetes.io/hostname
              labelSelector:
                matchLabels:
                  k8s-app: kube-dns
    servers:
      - zones:
          - zone: .
        port: 53
        plugins:
          - name: errors
          - name: health
            configBlock: |-
              lameduck 5s
          - name: ready
          - name: log
            parameters: .
            configBlock: |-
              class error
          - name: prometheus
            parameters: 0.0.0.0:9153
          - name: kubernetes
            parameters: cluster.local in-addr.arpa ip6.arpa
            configBlock: |-
              pods insecure
              fallthrough in-addr.arpa ip6.arpa
              ttl 30
          - name: forward
            parameters: . /etc/resolv.conf
            configBlock: |-
              max_concurrent 1000
          - name: cache
            parameters: 30
            configBlock: |-
              disable success cluster.local
              disable denial cluster.local
          - name: loop
          - name: reload
          - name: loadbalance
      - zones:
          - zone: futo.network
        port: 53
        plugins:
          - name: errors
          - name: cache
            parameters: 30
          - name: forward
            parameters: . ${local.netbird_dns_ip}
    YAML
  ]
}
