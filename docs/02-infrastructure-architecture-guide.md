# Infrastructure architecture guide

The OVH foundation under the cluster: compute, private network, and public ingress. Each environment is a fully independent build of the same shape; they differ only in worker tier and IPLB zone count.

> **Status:** staging is built and running (`o11y-staging`). Production is planned (`o11y-production`) — same shape, larger workers, multi-zone ingress.

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

## Operator access (Tailscale)

Tailscale runs as a Talos system extension on **every** node, so operators reach `talosctl` and `kubectl` over the tailnet without exposing those APIs publicly. Control planes advertise the private CIDR as a subnet route, auto-approved by the tailnet ACL; workers consume the routes. The ACL is environment-scoped (`tag:env-staging` vs `tag:env-production`) so staging operators can't pivot into production.

Operators point `kubectl`/`talosctl` at a specific control plane's static private IP — not the floating VIP, since cross-DC ARP for the VIP over Tailscale subnet routes is unreliable. The VIP remains the in-cluster apiserver endpoint used by kubelet and other in-cluster components.

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
| Tailscale tag | `tag:env-staging` | `tag:env-production` |
| Flux source | `staging` overlay | `production` overlay |
