# Infrastructure architecture guide

The OVH foundation under the cluster: compute, private network, and public ingress. Each environment is a fully independent build of the same shape; they differ only in worker tier and IPLB zone count.

> **Status:** both environments are built and running — `o11y-staging` and `o11y-production`. Same shape; production has larger workers and multi-zone ingress.

## Shape

One cluster per environment, **3 control planes + 3 workers**, stretched across DCs:

* **Control planes** run on OVH Public Cloud in **RBX-A + GRA9 + EU-WEST-PAR** — the three lowest-RTT DCs (worst pair ~5ms), comfortably inside etcd's latency tolerance. etcd keeps quorum with 2 of 3, so a single DC outage doesn't take the API down.
* **Workers** run on bare metal in **RBX + GRA + SBG**. Workers don't participate in etcd consensus, so the higher RTT to SBG is acceptable; pods reschedule to surviving DCs on a node or DC failure.

Storage is node-local (OpenEBS hostpath) — there is no replicated block storage across DCs. VictoriaMetrics replicates at the application layer, so this is by design. There is no inter-environment replication; each environment stands alone on its own vRack.

## Hardware

Staging specs are confirmed against the live cluster.

| Role | Plan | Spec | DCs |
|------|------|------|-----|
| Control plane | `b3-8` (Public Cloud) | 2 vCPU, 8 GB RAM, 50 GB NVMe, 4 Gbps private | RBX-A, GRA9, EU-WEST-PAR |
| Worker (staging) | `SYS-2` (`24sys022`, bare metal) | Intel Xeon D-2141I, 8c/16t, 32 GB ECC DDR4, 2× 512 GB NVMe (WDC CL SN720), 1 Gbps public + private | RBX, GRA, SBG |
| Worker (production) | `Rise-2` (`24rise02-v1`, bare metal) | Intel Xeon-E 2388G, 8c/16t, 128 GB ECC DDR4, 3× 1.92 TB NVMe, 1 Gbps public + 2 Gbps vRack | RBX, GRA, SBG |

Same control-plane tier in both environments. Production workers add RAM and a third NVMe to carry more observability storage; the exact tier is confirmed against OVH stock at order time.

## vRack (private L2)

All intra-cluster east-west traffic — etcd, apiserver, kubelet, flannel VXLAN, Spegel peering — rides OVH's **vRack**, an L2 network spanning every DC. Public Cloud private networks and bare-metal vRack interfaces share one untagged VLAN, so control planes and workers see each other as a single L2 segment. The vRack is also the trust boundary for the Talos host firewall.

Each environment has its own vRack **and** its own private CIDR — staging `10.150.200.0/24`, production `10.150.100.0/24` — so a misconfigured deploy in one environment cannot reach another over the private network. Every node gets a static private IP on its vRack interface. The control-plane API is reached at a Talos floating VIP at the `.5` of the environment's CIDR (`10.150.200.5` in staging).

## Public ingress: IP Load Balancing (IPLB)

Public ingress goes through a managed **OVH IP Load Balancing (`lb1` tier)** instance per environment. The LB takes backends **by IP**, so the bare-metal workers attach directly. Each LB zone gets a TCP `:443` front-end and farm; the farm forwards to the workers' **public** Envoy NodePort (`30443`) with PROXY protocol v2 so Envoy sees the real client IP. TLS terminates at Envoy.

The worker host firewall scopes `:30443` to OVH's IPLB NAT range (`10.108.0.0/14`). Those are OVH-internal RFC1918 addresses, so the public internet can't reach the port directly and can't spoof such a source past OVH's edge — the LB is the only ingress path. DNS for platform services points at the IPLB's public IP, managed by Terraform.

* **Staging** — single zone (`gra`). A single LB-zone outage takes staging ingress down, which is acceptable.
* **Production** — multi-zone anycast across `gra` + `rbx` + `sbg`: the same public IP is announced from each zone, so a single OVH-zone outage doesn't break ingress.

Because the farm targets the workers' public IPs (not the vRack), three things are required and are handled in the cluster config: NodePorts must answer on the public NIC, exactly one Envoy must run per worker, and Envoy must parse PROXY protocol. See the cluster architecture guide for those details.

## NetBird mesh

NetBird connects operators, other FUTO clusters, and the bootstrap cluster to this environment without exposing anything publicly. Everything is Terraform-managed (`netbird/cluster`, objects named `o11y-<env>-*`) and environment-scoped — separate groups, networks, and policies per environment, so staging access can't pivot into production. Four building blocks:

* **Node mesh (operator access).** NetBird runs as a Talos system extension on every node, and the vRack subnet is advertised as a network route with the Talos nodes as routing peers — any node can route, so it's HA. Operator traffic arrives masqueraded to the routing peer's vRack IP, which the host firewall already trusts. A policy grants the shared `yucca` operator group the management ports only (apid `50000`, kube-apiserver `6443`). This is the path `talosctl` and the Terraform providers use.
* **Workload ingress (mesh gateway).** In-cluster `netbird-router` pods are the routing peers for a pinned Envoy gateway VIP — a ClusterIP from a dedicated secondary ServiceCIDR, advertised as a `/32` resource. The pods exist because only pod-level routing can advertise a ClusterIP (kube-proxy's DNAT runs in the host netns). A NetBird DNS zone resolves `*.<mesh-domain>` to the VIP for mesh peers; the `yucca` group is allowed `:443` (mesh-facing HTTPRoutes) and `:6443` — the HA kube-apiserver endpoint `kube.<mesh-domain>`, which `kubectl` uses by default: it load-balances across every apiserver and never hairpins through a routing peer.
* **Pod egress (Multus).** Pods can't normally originate mesh traffic — NetBird only masquerades traffic sourced from ranges a peer advertises, and the flannel pod CIDR isn't one. Pods that need the mesh (today: the external-secrets controller, reaching the bootstrap cluster's 1Password Connect at `opc.o11y.futo.network`) opt in via a Multus `NetworkAttachmentDefinition`: a second interface in an egress range the nodes advertise, with a route scoped to just the opc VIP. The node's own NetBird carries it out; everything else stays on flannel.
* **Mesh DNS.** The router pods also serve NetBird DNS to the cluster: CoreDNS forwards the `futo.network` zone to a pinned `netbird-dns` Service in front of them, so any pod resolves mesh names (opc, mesh gateways) through ordinary cluster DNS with zero per-pod configuration.

All the ranges involved — the vRack, the gateway ServiceCIDR, and the egress CIDR — are registered in NetBox by the `netbox/cluster` module from the same Terraform values that allocate them.

Operators point `talosctl` at a control plane's static private IP over the node mesh (not the floating VIP — cross-DC ARP for the VIP is unreliable over the route; it remains the in-cluster apiserver endpoint). `kubectl` defaults to `kube.<mesh-domain>` through the mesh gateway, with a direct-CP break-glass context in the same kubeconfig for bootstrap/DR.

## Cost

USD, catalog-verified (OVH prices in GBP; converted at ~1.27×). Public Cloud instances bill hourly (shown × ~730 h/mo); workers and IPLB bill monthly; vRack is free.

| Component | Staging | Production | Setup (one-time) |
|-----------|---------|------------|------------------|
| Control plane | $123 (3× b3-8) | $123 (3× b3-8) | — |
| Workers | $163 (3× SYS-2) | $465 (3× Rise-2) | $221 |
| IPLB | $20 (1 zone) | $61 (3 zones) | — |
| **Total / mo** | **$306** | **$649** | **$221** |

Staging + production run-rate ≈ **$955/mo** plus the one-time **$221** production install fee — within the ~$1,000/month budget.

## Environment differences

| Parameter | Staging | Production |
|-----------|---------|------------|
| Cluster name | `o11y-staging` | `o11y-production` |
| Workers | 3× `SYS-2` (`24sys022`) | 3× `Rise-2` (`24rise02-v1`) |
| IPLB | 1 zone (`gra`) | 3 zones (`gra` + `rbx` + `sbg`), anycast |
| Private CIDR | `10.150.200.0/24` | `10.150.100.0/24` |
| Mesh domain | `staging.o11y.futo.network` | `o11y.futo.network` |
| Gateway ServiceCIDR (VIP `.10`) | `10.69.1.0/24` | `10.69.0.0/24` |
| Pod egress CIDR | `10.69.3.0/24` | `10.69.2.0/24` |
| NetBird objects | `o11y-staging-*` | `o11y-production-*` |
| Flux source | `staging` overlay | `production` overlay |
