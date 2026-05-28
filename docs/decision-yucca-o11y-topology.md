# Decision: Yucca O11y cluster topology

* **Date:** 2026-04-16 (last revised 2026-05-28)
* **ADR:** [Yucca O11y cluster topology](./adr-yucca-o11y-topology.md)

## Summary

We are going with **Option C — stretched single-cluster across nearby OVH regions**. This gives us the geographic resilience of the multi-cluster approach with the operational simplicity of a single cluster, at a cost that fits within budget.

> Pricing is from OVH's GB subsidiary (which bills in GBP). USD figures are converted at **~£1 = $1.27**.
>
> **Status by environment**
>
> * **Staging** — built and running.
> * **Production** — **TBD.** The sizing, regions, and per-DC node-count below are the working plan; nothing is ordered yet. Final hardware will be the SYS-2/Rise-2/ADV-1 tier that has stock in the chosen DCs at order time.

## Networking

* **OVH vRack** for all intra-cluster east-west traffic (etcd, apiserver, kubelet, flannel VXLAN, Spegel registry peering) and as the trust boundary for Talos's stateful host firewall.
* **OVH IP Load Balancing (IPLB, the standalone `ovh_iploadbalancing` service, Pack 1 / `lb1` tier)** for public ingress. The original plan was MetalLB L2 announcing an OVH Additional IP over the vRack; that was rejected during implementation because OVH's per-NIC anti-spoofing drops asymmetric replies sourced from the Additional IP. IPLB takes backends by IP, so bare-metal workers attach directly.
* **Tailscale** for operator access (kubectl, talosctl, flux) and as a fallback in-cluster route advertised by control planes.

## Operator access

Tailscale runs as a [Talos system extension](https://github.com/siderolabs/extensions/tree/main/network/tailscale) on **every node** (control planes and workers). This gives operators:

* `talosctl` and `kubectl` access to the API surfaces without exposing them on the public internet.
* A working fallback path even if a node's vRack interface is misconfigured.

`kubectl` and `talosctl` point at a specific control plane's **static private IP** (not the Talos floating VIP — cross-DC ARP propagation for the VIP over Tailscale subnet routes proved unreliable). All CP private IPs are in the apiserver cert SANs.

## Production *(TBD)*

The numbers below are the working plan; final OVH order tier depends on stock at order time.

### Control Plane — Public Cloud (RBX-A + GRA9 + EU-WEST-PAR)

Public Cloud instances — cheaper than bare metal and sufficient for CP workloads. Placed in the three lowest-latency DCs to keep etcd RTT under ~5ms.

| Node | Spec | Cost |
|------|------|------|
| b3-8 EU/FRA/RBX | 2 vCPU, 8GB RAM, 50GB NVMe, 500Mbps public, 4Gbps private | £32.19/mo (~$40.88/mo) |
| b3-8 EU/FRA/GRA | 2 vCPU, 8GB RAM, 50GB NVMe, 500Mbps public, 4Gbps private | £32.19/mo (~$40.88/mo) |
| b3-8 EU/FRA/PAR | 2 vCPU, 8GB RAM, 50GB NVMe, 500Mbps public, 4Gbps private | £32.19/mo (~$40.88/mo) |

**Subtotal:** ~£97/mo (~$123/mo)

### Workers — Bare Metal Rise-2 (RBX + GRA + SBG)

The `<10ms` etcd constraint applies to control plane nodes only. Workers do not participate in etcd consensus, so the higher latency to SBG (~9.8ms to RBX, ~10.4ms to GRA) is acceptable.

Configured with upgraded RAM (128GB), storage (3x 1.92TB NVMe), and private bandwidth (2Gbps).

| Node | Spec | Cost |
|------|------|------|
| Rise-2 EU/FRA/RBX | Intel Xeon-E 2388G, 8c/16t, 128GB DDR4 ECC, 3x 1.92TB NVMe, 1Gbps public, 2Gbps private | £122.06/mo (~$155.02/mo) |
| Rise-2 EU/FRA/GRA | Intel Xeon-E 2388G, 8c/16t, 128GB DDR4 ECC, 3x 1.92TB NVMe, 1Gbps public, 2Gbps private | £122.06/mo (~$155.02/mo) |
| Rise-2 EU/FRA/SBG | Intel Xeon-E 2388G, 8c/16t, 128GB DDR4 ECC, 3x 1.92TB NVMe, 1Gbps public, 2Gbps private | £122.06/mo (~$155.02/mo) |

**~£366/mo (~$465/mo)** (one-time installation: £173.97 / ~$221)

**Fallback:** If Rise-2 stock is unavailable in a target DC, ADV-1 servers (AMD EPYC 4245P, 6c/12t, 64GB RAM, 4x 1.92TB, 3Gbps public, 25Gbps private) are confirmed available in all three regions at ~£197/mo (~$250) each (~£592/mo / ~$752/mo total).

### Service exposure

A **multi-zone OVH IP Load Balancing (`lb1`)** service holds the public IP. Each LB zone (`gra`, `rbx`, `sbg`) gets its own TCP `:443` front-end and farm, all sharing the same public IP — this is anycast: the IPLB announces the same address from each zone, so a single OVH-zone outage doesn't take ingress down.

The farms forward L4 to the workers' **public** Envoy NodePort (`30443`); the worker firewall scopes that port to OVH's IPLB NAT/source range (`10.108.0.0/14`) so only the LB can reach it. TLS terminates at Envoy Gateway (`ClientTrafficPolicy` with PROXY protocol v2). DNS for platform services points at the IPLB's single public IP.

Each extra LB zone is **+£15.99/mo (~$20/mo)**. We deliberately stay on the `lb1` tier — `lb2` would unlock vRack-eligible backends (so the `30443` hole could be private-only) but at ~10× the cost (£152.99/mo / ~$194/mo per zone), and the `10.108.0.0/14` lockdown already gives us LB-only ingress without it.

**Fallback:** If anycast `lb1` proves problematic, a single-zone `lb1` in `gra` (matching staging) is the smaller-blast-radius backstop. Worker-side configuration is identical either way.

### Production budget *(TBD)*

| Component | Cost |
|-----------|------|
| Control plane (3x b3-8) | ~£97/mo (~$123/mo) |
| Workers (3x Rise-2) | ~£366/mo (~$465/mo) |
| IPLB lb1 (3 zones, anycast) | ~£48/mo (~$61/mo) |
| **Total** | **~£511/mo (~$649/mo)** |

Within the ~$1,000/month budget.

## Staging

Staging mirrors the production topology (stretched across the same DCs) to validate cross-DC behaviour, etcd latency, and Flux deployments before promoting to production. Workers use a smaller bare metal tier to reduce cost.

### Control Plane — Public Cloud (RBX-A + GRA9 + EU-WEST-PAR)

Same b3-8 tier as production so we exercise the actual CP behaviour in staging. (Earlier sizing used `d2-8` in two regions to save ~£28/mo, but b3-8's 4Gbps private bandwidth matches what production needs and the cost difference is negligible at this scale.)

| Node | Spec | Cost |
|------|------|------|
| b3-8 EU/FRA/RBX | 2 vCPU, 8GB RAM, 50GB NVMe, 500Mbps public, 4Gbps private | £32.19/mo (~$40.88/mo) |
| b3-8 EU/FRA/GRA | 2 vCPU, 8GB RAM, 50GB NVMe, 500Mbps public, 4Gbps private | £32.19/mo (~$40.88/mo) |
| b3-8 EU/FRA/PAR | 2 vCPU, 8GB RAM, 50GB NVMe, 500Mbps public, 4Gbps private | £32.19/mo (~$40.88/mo) |

**Subtotal:** ~£97/mo (~$123/mo)

### Workers — SoYouStart SYS-2 (RBX + GRA + SBG)

SYS-2 bare metal — Broadcom NetXtreme-E NICs (predictable `eno1np0` / `eno2np1` naming), one 512GB WDC SN720 NVMe used as the system disk + carved into Talos UserVolumes for general PV storage, one as a dedicated `local-hostpath` UserVolume for workloads that benefit from PV isolation (primarily VictoriaMetrics' `vmstorage`).

| Node | Spec | Cost (approx.) |
|------|------|------|
| SYS-2 EU/FRA/RBX | Intel Xeon-E 2386G, 6c/12t, 64GB DDR4 ECC, 2x 512GB NVMe, 1Gbps public, 1Gbps private | £64/mo (~$81/mo) |
| SYS-2 EU/FRA/GRA | Intel Xeon-E 2386G, 6c/12t, 64GB DDR4 ECC, 2x 512GB NVMe, 1Gbps public, 1Gbps private | £64/mo (~$81/mo) |
| SYS-2 EU/FRA/SBG | Intel Xeon-E 2386G, 6c/12t, 64GB DDR4 ECC, 2x 512GB NVMe, 1Gbps public, 1Gbps private | £64/mo (~$81/mo) |

**~£192/mo (~$244/mo)** (approximate — exact SYS-2 sub-tier and price vary with OVH stock at order time)

### Service exposure

A **single-zone OVH IP Load Balancing (`lb1`) in `gra`** — same model as production but one zone instead of three. An LB-zone outage takes staging ingress down, which is acceptable for staging. Worker firewall and Envoy configuration are identical to production.

A separate DNS root and IPLB instance keep staging ingress isolated from production.

### Staging budget

| Component | Cost |
|-----------|------|
| Control plane (3x b3-8) | ~£97/mo (~$123/mo) |
| Workers (3x SYS-2) | ~£192/mo (~$244/mo) |
| IPLB lb1 (1 zone, `gra`) | ~£16/mo (~$20/mo) |
| **Total** | **~£305/mo (~$387/mo)** |

## Combined budget

| Environment | Cost |
|-------------|------|
| Production *(TBD)* | ~£511/mo (~$649/mo) |
| Staging | ~£305/mo (~$387/mo) |
| **Total** | **~£816 (~$1,036) /mo** |

## Consequences

### Latency

* No replicated block storage — node-local only (OpenEBS hostpath, per-node)
* Control plane inter-node RTT: `<5ms` (RBX + GRA + PAR)
* Worker-to-control-plane RTT: `<10ms`

### Ingress

* The `30443` hole on workers' public NICs is scoped to OVH's IPLB NAT range (`10.108.0.0/14`); the LB is the only ingress path. If OVH ever enables vRack eligibility on `lb1`, ingress moves back onto the private network and the hole closes entirely.
* Each Envoy Service is `externalTrafficPolicy: Local` (preserves the client connection), so the `EnvoyProxy` deployment runs `replicas: 3` with a hostname `topologySpreadConstraint` — exactly one Envoy per worker, otherwise an Envoy-less worker fails its LB probe.
* `kube-proxy --nodeport-addresses=0.0.0.0/0` is required: in nftables mode kube-proxy defaults NodePorts to the node's primary IP (private vRack IP here), so without this `30443` never answers on the public NIC.

### Ingress sizing by env

* **Staging** runs single-zone `lb1` in `gra` (cheapest; a single LB-zone outage is acceptable in staging).
* **Production** runs multi-zone `lb1` anycast across `gra`, `rbx`, `sbg` — survives a single OVH-zone outage and matches the multi-DC cluster. Each extra zone is +£15.99/mo (~$20/mo), so it's cheap resilience.

### Operator surface

* Tailscale extension on every node (CPs and workers). Workers run it with `TS_ROUTES` empty — they're on the tailnet purely to keep the Talos image schematic uniform; if the extension is installed but not configured the node sits in a perpetual extension-failed state.
* Talos image schematic differs between CP and worker images:
  * **CP** (Public Cloud / KVM): tailscale + qemu-guest-agent
  * **Worker** (bare metal): tailscale only — qemu-guest-agent wedges bare-metal boot
