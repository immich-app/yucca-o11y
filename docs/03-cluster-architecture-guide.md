# Cluster architecture guide

How the cluster itself is built: the Talos operating system, the Kubernetes layer, and the Flux GitOps that drives everything on top.

## Talos

Talos Linux on every node, with flannel CNI and kube-proxy in nftables mode.

### Image schematics

Control planes and workers use **different** Talos Factory schematics, on purpose:

| Node type | Platform | Schematic |
|-----------|----------|-----------|
| Control plane | OVH Public Cloud (KVM) | `tailscale` + `qemu-guest-agent` |
| Worker | Bare metal | `tailscale` only |

`qemu-guest-agent` on bare metal wedges boot — it waits on a virtio-serial port that isn't present and reboot-loops the node. The control-plane image is an OpenStack image uploaded to OVH glance once; workers are BYOI and fetch their raw image from the Factory at order time.

### Machine configuration

* **Control-plane endpoint** is the floating VIP (`10.150.200.5`); the apiserver cert SANs include the VIP and every CP private IP, so operators can reach the API on any individual CP when the VIP doesn't ARP across DCs.
* **Component metrics** for kube-controller-manager, kube-scheduler, and etcd bind to all interfaces rather than localhost, so VMAgent (running on a worker) can scrape them. The host firewall keeps these ports private. The controller-manager and scheduler endpoints are authenticated HTTPS; etcd's is plain HTTP, so the firewall is its only protection.
* **kube-proxy** is told to answer NodePorts on every interface (not just the node's primary vRack IP), so the IPLB can reach Envoy on the workers' public NIC; its own metrics endpoint is likewise bound for scraping. These settings are generated into the cluster-wide kube-proxy DaemonSet.
* **Flannel's VXLAN endpoint** is pinned to the vRack interface; otherwise it defaults to the public NIC and the host firewall drops east-west pod traffic.

### Worker storage

Each worker has two NVMe drives. Talos carves the **system disk** into a fixed **EPHEMERAL** partition (container image cache and kubelet working dirs, wiped on factory-reset) and a growing **hostpath** UserVolume that backs the default `openebs-system-disk` StorageClass — used for the vmagent buffer, vmselect cache, and app config.

The **second NVMe** is a separate `local-hostpath` UserVolume backing the `openebs-spare-disk` StorageClass, reserved for workloads isolated from the general pool: VictoriaMetrics `vmstorage` and Grafana's CloudNativePG Postgres. The spare disk is matched by exact model so a re-provision on different hardware fails loudly rather than silently grabbing the wrong disk. Control planes use the default Talos layout.

### Host firewall

Default-deny ingress on every node; anything not listed is dropped at the host. Allowed:

| Service | Port(s) | Allowed sources |
|---------|---------|-----------------|
| apid | 50000/tcp | Tailscale (`100.64.0.0/10`, `fd7a:115c:a1e0::/48`), vRack |
| trustd | 50001/tcp | Tailscale, vRack |
| kube-apiserver (CPs) | 6443/tcp | Tailscale, vRack |
| etcd (CPs) | 2379–2380/tcp | vRack |
| kubelet | 10250/tcp | vRack + pod CIDR `10.244.0.0/16` |
| flannel VXLAN | 4789/udp | vRack |
| Spegel registry (workers) | 29999/tcp, 30021/tcp | vRack |
| Envoy ingress (workers) | 30443/tcp | `10.108.0.0/14` (IPLB NAT range only) |
| CP component metrics (CPs) | 10257, 10259, 2381/tcp | vRack + pod CIDR |
| Node metrics (all nodes) | 10249, 9100/tcp | vRack + pod CIDR |

Pod CIDR is allowed on `kubelet` and the metrics ports because pod-to-own-node-IP traffic skips flannel masquerade (a same-node scrape keeps its pod-IP source), which the vRack-only rule would otherwise drop.

## Kubernetes

Kubernetes with flannel CNI and kube-proxy in nftables mode. Spegel runs as a peer-to-peer image registry mirror so each node's containerd pulls layers from its peers before the upstream registry (this requires `discard_unpacked_layers = false` in the worker containerd config).

**Control-plane scraping** is wired end to end: the component metrics endpoints are bound off localhost (above), the host firewall scopes them to the vRack and pod CIDR, and VMAgent scrapes kube-controller-manager, kube-scheduler, etcd, kube-proxy, and the node-exporter DaemonSet.

## Flux GitOps

Everything above the OS is managed by Flux v2. Manifests are organized as reusable bases plus per-environment overlays:

* **`kubernetes/apps/base/`** holds the chart sources and reusable manifests.
* **`kubernetes/apps/<env>/`** holds the per-app Flux Kustomizations — each pins its chart version and declares its `dependsOn` ordering.
* **`kubernetes/clusters/<env>/apps.yaml`** is the `cluster-apps` entry point the Flux Instance points at.

### Version pinning

Chart (and the CloudNativePG Postgres image) versions are pinned per environment in the overlay Kustomization patches, so a version can be promoted in staging and soaked before production moves. Versions are renovate-managed in those patches; component versions are not documented here because they change continuously — the manifests are the source of truth.

### Configuration substitution

Per-environment values are **not** hardcoded in `base/` and **not** patched into each overlay. Instead, `cluster-apps` carries a single patch that targets every child Kustomization and injects a `postBuild.substituteFrom` pointing at the `cluster-settings` ConfigMap. Flux's envsubst then resolves placeholders at apply time. The variables:

| Variable | Staging | Consumed by |
|----------|---------|-------------|
| `APP_DOMAIN` | `staging.futostat.us` | cert `dnsNames`; HTTPRoute hostnames (Grafana, vmauth, echo) |
| `ALT_DOMAIN` | `staging.futostatus.com` | secondary-domain cert + routes |
| `CLUSTER_NAME` | `o11y-staging` | VictoriaMetrics `externalLabels.cluster` |

Because of this, values that vary by environment (domains, cluster name) live once in `base/` with a placeholder rather than being duplicated across overlays — only versions are still patched per environment. A rendered object can be checked exactly as Flux will produce it using the `flate` CLI.
