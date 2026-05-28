# Infrastructure: Yucca O11y cluster

* **Date:** 2026-04-21 (last revised 2026-05-28)
* **Decision:** [Yucca O11y cluster topology](./decision-yucca-o11y-topology.md)

This document covers the concrete configuration for both staging and production clusters. The topology is identical between environments — what differs is the node specs, the cluster name, the Tailscale env tag, and the IPLB zone count. Environment-specific values are called out where they appear.

> **Status by environment**
>
> * **Staging** — built and running. Cluster name `o11y-staging`, IPLB single-zone in `gra`.
> * **Production** — **TBD.** Cluster name will be `o11y-production`; IPLB multi-zone anycast across `gra` + `rbx` + `sbg`. Sizing per the [Decision](./decision-yucca-o11y-topology.md#production-tbd).

## OVH infrastructure

### vRack

Each environment gets its own vRack for full L2 isolation. Two vRacks (one per env) means a misconfigured staging deploy can't reach production over the private network, and we don't have to coordinate private IP allocations between envs.

| Environment | vRack | CIDR |
|-------------|-------|------|
| Staging     | `pn-stg`  | `10.150.200.0/24` |
| Production *(TBD)* | `pn-prod` | `10.150.200.0/24` (same — isolated by vRack) |

Since each vRack is a separate L2 network, both environments can use the same private CIDR. The only per-environment difference is which vRack the node is attached to.

All bare metal servers and Public Cloud instances for a given environment are attached to that environment's vRack. Each node gets a static private IP on its vRack interface.

vRacks are free.

### Public ingress: IP Load Balancing (IPLB)

Ingress goes through a managed **OVH IP Load Balancing (`ovh_iploadbalancing`, Pack 1 / `lb1` tier)** instance per environment. The LB takes backends **by IP**, so the bare-metal workers attach directly.

| Environment | IPLB zones | Topology | Cost |
|-------------|------------|----------|------|
| Staging     | `gra` (1)  | Single-zone | ~£16/mo |
| Production *(TBD)* | `gra`, `rbx`, `sbg` (3) | Multi-zone anycast (same public IP from each zone) | ~£48/mo |

For each zone the terraform module creates one `ovh_iploadbalancing_tcp_frontend` on `:443` and one `ovh_iploadbalancing_tcp_farm`; the farm's `tcp_farm_server` entries point at the workers' **public IPs** on NodePort `30443`, with `proxy_protocol_version = "v2"` so Envoy sees the real client IP. `vrackEligibility` is **false** on `lb1` — that's deliberate: paying ~10× for `lb2` to unlock vRack-eligible backends would only buy architectural tidiness (private-only backends), since the `10.108.0.0/14` source-scope on `:30443` already restricts ingress to the LB.

DNS points at the IPLB's public IP. In multi-zone production the IP is anycast — OVH announces the same address from each zone, so a single OVH-zone outage doesn't break ingress.

### Server provisioning

Servers are provisioned via Terragrunt using a 4-layer pattern: `ovh/account` → `tailscale/account` → `talos/cluster` → `kubernetes/helm`. Public Cloud instances (control plane) are created via the OVH Terraform provider. Bare metal workers are BYOI-provisioned by OVH from the worker schematic at order time and attached to the environment's vRack.

All servers have:

* vRack private interface enabled and configured with a static IP from the environment's CIDR (`eno2np1` on SYS-2 workers; the equivalent on b3-8 instances).
* Public interface DHCP-configured (`eno1np0` on workers) — used by `kubelet → apiserver`, image pulls, outbound internet, the IPLB → `:30443` ingress path on workers, and Tailscale.

## Talos Linux

Talos `v1.13.0`. Kubernetes `v1.36`. CNI **flannel** with kube-proxy in **nftables mode**.

### Image schematic

Talos images are built via the [Talos Image Factory](https://factory.talos.dev). **Control planes and workers use different schematics** — this is intentional:

| Node type | Platform | Schematic |
|-----------|----------|-----------|
| Control plane | OpenStack (OVH Public Cloud, KVM) | `tailscale` + `qemu-guest-agent` |
| Worker        | Bare metal (raw image)           | `tailscale` only |

`qemu-guest-agent` on bare metal **wedges boot and reboot-loops the node** — it expects a virtio-serial port that isn't there. Keeping the schematics distinct also means the CP image (an OpenStack `raw.xz`) is downloaded and uploaded to glance once (`mise run talos:dl:cp && mise run talos:ul:cp`), while the worker schematic is BYOI — OVH fetches the worker `raw` from the Factory at server-order time, no upload needed.

### Control plane machine config

Control planes run etcd, the Kubernetes API server, and the Tailscale extension. The disk install image is the OVH glance-uploaded CP image; the cluster endpoint is a Talos floating VIP on the vRack.

```yaml
machine:
  type: controlplane
  install:
    image: factory.talos.dev/installer/<cp-schematic-id>:v1.13.0
  network:
    hostname: <env>-cp-<dc>     # e.g. staging-cp-gra, production-cp-rbx
    interfaces:
      # Public NIC — DHCP, used for initial provisioning, outbound, and Tailscale
      - interface: <public-iface>
        dhcp: true
      # vRack NIC — static private IP from env CIDR
      - interface: <vrack-iface>
        addresses: [10.150.200.X/24]
  certSANs:
    - 10.150.200.10              # all CP private IPs are in SANs
    - 10.150.200.11
    - 10.150.200.12

cluster:
  controlPlane:
    endpoint: https://10.150.200.10:6443   # Talos floating VIP on the vRack
```

### Worker machine config

Workers run the Tailscale extension (with `TS_ROUTES` empty) to keep the image schematic uniform, even though operators don't reach them through the tailnet. They also enable `discard_unpacked_layers = false` in containerd config so Spegel can serve image layers peer-to-peer.

```yaml
machine:
  type: worker
  install:
    image: factory.talos.dev/installer/<worker-schematic-id>:v1.13.0
  network:
    hostname: <env>-worker-<dc>  # e.g. staging-worker-sbg
    interfaces:
      - interface: eno1np0       # public NIC — DHCP
        dhcp: true
      - interface: eno2np1       # vRack NIC — static
        addresses: [10.150.200.X/24]
  files:
    - op: create
      path: /etc/cri/conf.d/20-customization.part
      content: |
        [plugins."io.containerd.cri.v1.images"]
          discard_unpacked_layers = false   # required by Spegel
```

NIC names match the Broadcom NetXtreme-E predictable scheme on SYS-2 hardware. A future re-provision on a different chipset would need a switch to `deviceSelector.physicalAddress` (MAC).

### Cluster config

Shared across both node types via the `cluster` block of the Talos machine config.

```yaml
cluster:
  clusterName: o11y-<env>        # o11y-staging or o11y-production
  network:
    podSubnets:    [10.244.0.0/16]
    serviceSubnets: [10.96.0.0/12]
    cni:
      name: flannel
  proxy:
    extraArgs:
      # NodePorts must answer on the public NIC (the IPLB reaches Envoy via the
      # worker's public IP). Without this, kube-proxy nftables defaults NodePorts
      # to the node's primary IP — the private vRack IP — and the LB sees nothing.
      nodeport-addresses: "0.0.0.0/0"
```

### Worker storage layout

Each SYS-2 worker has two 512GB NVMe drives. The first (`system_disk`) is carved by Talos into:

* **EPHEMERAL** — 256GB fixed (`grow: false`). Container image cache + kubelet working dirs. Wiped on factory-reset.
* **`hostpath` UserVolume** — the rest of the system disk (≥20GB, grows). Backs the default `openebs-system-disk` StorageClass.

The second NVMe is brought up as a separate **`local-hostpath` UserVolume** (≥100GB, grows). Backs an `openebs-spare-disk` StorageClass for workloads isolated from the general PV pool — primarily VictoriaMetrics' `vmstorage`. The diskSelector matches **by exact model** (`disk.model == "WDC CL SN720 SDAQNTW-512G-2000" && !system_disk`) so a future re-provision on different hardware fails loudly rather than silently picking another disk.

CPs use the Talos default layout (one EPHEMERAL on the install disk).

### Host firewall (Talos `NetworkRuleConfig`)

Default `NetworkDefaultActionConfig: block` for ingress on every node — anything not explicitly allowed is dropped at the host. Allowed rules:

| Service | Port(s) | Allowed sources |
|---------|---------|-----------------|
| apid    | 50000/tcp | Tailscale (`100.64.0.0/10`, `fd7a:115c:a1e0::/48`), vRack CIDR |
| trustd  | 50001/tcp | Tailscale, vRack |
| kube-apiserver (CPs) | 6443/tcp | Tailscale, vRack |
| etcd (CPs) | 2379–2380/tcp | vRack |
| kubelet | 10250/tcp | vRack CIDR **+ pod CIDR `10.244.0.0/16`** |
| flannel VXLAN | 4789/udp | vRack |
| Spegel registry (workers) | 29999/tcp, 30021/tcp | vRack |
| Envoy ingress (workers) | 30443/tcp | **`10.108.0.0/14`** (OVH IPLB NAT range only) |

The pod CIDR allowance on `kubelet` is required because pod-to-own-node-IP traffic skips flannel masquerade — metrics-server colocated with a node it scrapes keeps its pod-IP source IP, and would otherwise be dropped by the vRack-only allow rule.

The `10.108.0.0/14` source-scope on `:30443` is the IPLB's NAT/source range, retrieved from `/ipLoadbalancing/{serviceName}/natIp` and confirmed by packet capture (the LB connects from `10.110.x.x` inside that block). Those are OVH-internal RFC1918 addresses, so the public internet can't reach `:30443` directly and can't spoof such a source past OVH's edge — the LB is the only ingress path.

## Tailscale

### Extension configuration

Tailscale runs on every node via Talos `ExtensionServiceConfig`. Auth keys are reusable, ephemeral, pre-authorized, and tagged.

```yaml
name: tailscale
apiVersion: v1alpha1
kind: ExtensionServiceConfig
environment:
  - TS_AUTHKEY=<auth-key>
  - TS_HOSTNAME=<node-name>
  - TS_EXTRA_ARGS=--accept-dns=false
```

The auth keys are minted by terraform per node (`tailscale_tailnet_key.{controlplane,worker}` in `talos/cluster`), tagged with both `tag:project-yucca` and `tag:env-<environment>`.

### ACL policy

Tailscale ACLs (managed by `tailscale/account`) restrict access:

* `tag:project-yucca` nodes can talk to each other on Talos and Kubernetes API ports.
* `group:o11y-team` members can reach the env tags on `:50000` (Talos) and `:6443` (kubelet/apiserver).
* Tags are env-scoped (`tag:env-staging` vs `tag:env-production`) so staging operators can't accidentally pivot into production.

### Operator usage

```bash
# Talos API
talosctl -n 10.150.200.10 health

# Kubernetes API (kubeconfig points at one CP's static private IP, in cert SANs)
kubectl get nodes
```

`kubectl` doesn't go through the floating VIP — cross-DC ARP propagation for the VIP over Tailscale subnet routes proved unreliable. The VIP remains the in-cluster apiserver endpoint (used by kubelet and other in-cluster components).

## Kubernetes platform

Apps are managed by Flux v2 GitOps. Charts come from the OCI registries listed; renovate-pinned tags live in env overlay Kustomization patches.

| Component | Chart | Notes |
|-----------|-------|-------|
| **cert-manager** | `oci://quay.io/jetstack/charts/cert-manager` | v1.19.4 |
| **cert-manager-webhook-ovh** | `oci://ghcr.io/aureq/charts/cert-manager-webhook-ovh` | 0.9.10. ACME DNS-01 against the OVH API. Issuers use Let's Encrypt with `profile: shortlived`. |
| **Envoy Gateway** | `oci://docker.io/envoyproxy/gateway-helm` | v1.7.0. `EnvoyProxy` `replicas: 3` with hostname `topologySpreadConstraint` — exactly one Envoy per worker. `Service` is `type: NodePort` (`nodePort: 30443`), `externalTrafficPolicy: Local`. `ClientTrafficPolicy` parses PROXY protocol v2 with `optional: true` so the IPLB's bare-TCP health probe isn't reset. |
| **Spegel** | `oci://ghcr.io/spegel-org/helm-charts/spegel` | 0.7.1. Peer-to-peer image registry mirror — every node's containerd pulls from its peers first, the upstream registry second. Requires `discard_unpacked_layers = false` in containerd config. |
| **descheduler** | `oci://ghcr.io/home-operations/charts-mirror/descheduler` | 0.36.0 |
| **reloader** | `oci://ghcr.io/stakater/charts/reloader` | 2.2.12 |
| **metrics-server** | `oci://ghcr.io/home-operations/charts-mirror/metrics-server` | 3.13.0 |

### TLS certificates

Certificates are short-lived ECDSA P-256 with always-rotate:

```yaml
spec:
  duration: 160h
  privateKey:
    algorithm: ECDSA
    size: 256
    rotationPolicy: Always
  usages:
    - digital signature
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt-production
```

Per-env overlays patch in the env-appropriate `dnsNames` (e.g. `*.staging.futostat.us` + `staging.futostat.us`).

## Environment differences

Everything above applies to both environments. The only differences:

| Parameter | Staging | Production *(TBD)* |
|-----------|---------|--------------------|
| Cluster name        | `o11y-staging` | `o11y-production` |
| vRack               | `pn-stg`   | `pn-prod` |
| vRack CIDR          | `10.150.200.0/24` | `10.150.200.0/24` (same — isolated by vRack) |
| CP nodes            | 3x b3-8 (RBX-A, GRA9, EU-WEST-PAR) | 3x b3-8 (RBX-A, GRA9, EU-WEST-PAR) |
| Worker nodes        | 3x SYS-2 (RBX, GRA, SBG) | 3x Rise-2 (RBX, GRA, SBG) — or ADV-1 fallback |
| IPLB zones          | 1 (`gra`) | 3 (`gra` + `rbx` + `sbg`), anycast |
| Tailscale env tag   | `tag:env-staging` | `tag:env-production` |
| Talos version       | Pinned, updated first | Pinned, promoted from staging |
| Flux source         | `staging` overlay | `production` overlay |

## Bootstrap order

Order matters because Tailscale isn't running until the cluster is partially up:

1. **OVH** — order Public Cloud instances + bare metal workers, create vRack, attach servers, create IPLB + farms + frontends.
2. **Tailscale** — sync ACL + tailnet settings.
3. **Talos cluster (bootstrap mode)** — `TF_VAR_use_public_endpoints=true` forces talosctl to reach nodes over their public IPs (Tailscale isn't up yet). Apply machine configs, bootstrap etcd, wait for Kubernetes API.
4. **Talos cluster (steady state)** — re-apply with `use_public_endpoints=false`; talosctl pivots to private IPs over the vRack/Tailscale. Host firewall closes the public NIC (everything except `:30443` on workers).
5. **Kubernetes/helm** — install cert-manager bootstrap secrets, OVH webhook DNS credentials, external-secrets 1Password token.
6. **Flux** — `flux bootstrap`, then GitOps takes over the rest (Envoy Gateway, Spegel, descheduler, reloader, metrics-server, workloads).

## Tooling

* **OpenTofu** + **Terragrunt** for IaC (version pins in `.mise/config.toml`)
* **Terraform providers**: `ovh`, `tailscale`, `kubernetes`, `helm`, `siderolabs/talos` (version pins in each module's `config.tf`; lock files committed)
* **mise** drives tool versions and task wrappers (`tg`, `tg:fmt`, `tf:plan`, `tf:apply`, …)
* **1Password CLI** (`op run --env-file deployment/.env`) injects API credentials at terragrunt invocation time
