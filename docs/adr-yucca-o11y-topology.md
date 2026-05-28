# Yucca O11y Topology — ADR

**Status:** Accepted

**Scope:** The runtime topology of the Yucca O11y platform — number of clusters, node placement, networking, ingress, operator access, storage layout.

## Context

The platform serves multiple internal users (observability dashboards, metrics ingest, alerting) and needs to be:

1. **Highly available** to a single-DC failure — the previous v1 setup put each env on a single-node cluster per region and lost everything if that one DC went down or the node was rebooted.
2. **Cheap enough** that staging can be a full peer of production without doubling the cost.
3. **Operator-friendly** — config changes, version bumps, and ad-hoc debugging shouldn't require special bastion access or per-DC kubeconfigs.
4. **Self-contained per env** — no leaky cross-env dependencies; a misconfigured staging deploy shouldn't be able to affect production.

We're already an OVH customer with a vRack across multiple European DCs, which makes cross-DC L2 cheap.

## Decision

One **stretched Kubernetes cluster per environment**, six nodes across four DCs:

- **3 control-plane nodes** on OVH Public Cloud (`b3-8`), placed in RBX-A, GRA9, EU-WEST-PAR. These three cities have <5 ms RTT between them — fast enough for an etcd quorum.
- **3 worker nodes** on OVH bare-metal in RBX, GRA, SBG. Different DCs from the CPs where possible, to spread workload-availability risk independently of CP-availability risk.

Everything is glued together by **one OVH vRack** providing real L2 connectivity across all four DCs. The CPs' Public Cloud private network and the workers' vRack interface share one untagged VLAN, so the entire cluster sees itself as one L2 segment.

### Ingress

A single **OVH IP Load Balancing (IPLB)** service (`ovh_iploadbalancing`, the standalone managed LB) holds the public IP. A TCP `:443` farm forwards **L4** to the workers' Envoy **NodePort (`30443`)**; TLS passes through and terminates at Envoy (the wildcard certs stay on Envoy). Everything behind it is ClusterIP-only.

The IPLB takes backends **by IP**, so the bare-metal workers attach directly — unlike the OpenStack **Octavia** LB (`ovh_cloud_project_loadbalancer`), which only accepts OpenStack-allocated backends and forces a gateway-enabled subnet that breaks the CPs' egress (see *Ingress LB options* under Alternatives).

The farm targets the workers' **public IPs**, not their vRack IPs. We intended to attach the IPLB to the vRack and reach the private NodePort, but the `lb1` order came back **`vrackEligibility: false`** — OVH does not grant vRack on new IPLB orders here — so the LB can only reach backends over routable IPs. This is still sound: each worker replies to the LB from its **own** public IP (not a foreign Additional IP), so OVH's per-NIC anti-spoofing doesn't drop it — the return-path asymmetry that made MetalLB unworkable doesn't apply. The cost is a public-NIC firewall hole for `30443` on the workers — but scoped to the IPLB's NAT range so only the LB can use it (see *Public NIC lockdown*).

Three implementation details this forces:

- **kube-proxy `--nodeport-addresses=0.0.0.0/0`** (`cluster.proxy.extraArgs`). In nftables mode kube-proxy defaults NodePorts to the node's *primary* IP — the private vRack IP here — so the public NIC never answered `30443` and every LB probe was dead until this was set.
- **One Envoy per worker.** The Envoy Service is `externalTrafficPolicy: Local` (preserves the connection, no extra hop), so a worker without a local Envoy pod fails its LB probe. The `EnvoyProxy` runs `replicas: 3` with a hostname `topologySpreadConstraint` pinning exactly one per worker.
- **PROXY protocol v2.** Because the LB is the TCP peer, Envoy would otherwise log the LB's outbound IP as the client. The farm-servers prepend a PROXY v2 header and Envoy's `ClientTrafficPolicy` parses it into `X-Forwarded-For` (`optional: true`, so the bare-TCP health probe isn't reset).

### Operator access

The cluster's in-cluster apiserver endpoint is a Talos **floating VIP** on the private network, elected via etcd. Kubelets and other in-cluster components use it.

Operators **don't** use the VIP. Cross-DC ARP for floating IPs has proven unreliable when routed over Tailscale subnet routes, so the operator path is:

- Tailscale extension on every node (CPs advertise the env's private CIDR as a subnet route, auto-approved via tailnet ACL)
- Operator's host accepts the subnet route
- kubectl/talosctl point at a specific CP's **static private IP**, which is in the apiserver cert SANs

### Public NIC lockdown

Talos's in-host ingress firewall (`NetworkDefaultActionConfig: block` + `NetworkRuleConfig`) drops all inbound to apid (50000), trustd (50001), kube-apiserver (6443), etcd (2379–2380), and kubelet (10250) on the public NIC. Allowed source CIDRs: Tailscale CGNAT (`100.64.0.0/10`) and the vRack CIDR.

The one public-NIC hole is the Envoy ingress NodePort (`30443`, workers only), and it's scoped to the IPLB's NAT/source range **`10.108.0.0/14`** — the private block the LB connects from (OVH's `/ipLoadbalancing/{serviceName}/natIp`; confirmed by packet capture, the LB reaches the workers from `10.110.x.x` inside that range). Those are OVH-internal RFC1918 addresses, so the public internet can't reach `30443` directly and can't spoof such a source past OVH's edge — the LB is the only ingress path. Everything else stays default-deny.

### Storage

Workers carve their first NVMe into:

- **EPHEMERAL** — 256 GB fixed, for the container image cache and kubelet working dirs. Wiped on Talos factory-reset.
- **`hostpath` UserVolume** — the rest of the disk, mounted at `/var/mnt/hostpath`, backing the `openebs-system-disk` default StorageClass.

The second NVMe is brought up as a separate **`local-hostpath` UserVolume** at `/var/mnt/local-hostpath`, backing an `openebs-spare-disk` StorageClass for workloads that benefit from being isolated from the general PV pool — primarily VictoriaMetrics' `vmstorage`.

CPs use the Talos default disk layout (one big EPHEMERAL on the install disk).

## Alternatives considered

### Per-region clusters (v1)

What we had before. Each region was its own single-node cluster; observability data was federated via VMAuth read-fanout. **Rejected** because:

- Any single node reboot took an entire region offline.
- Federation logic added significant operational surface.
- Three separate clusters meant 3× the Flux config, Tailscale acls, secrets sync, etc.

### Per-region clusters with cross-region replication

Three independent multi-node clusters with VictoriaMetrics vmcluster running across them, replicating metrics. **Rejected** because:

- Still 3× the cluster-level config to maintain.
- Cross-region etcd quorum is achievable but the operational complexity (manual VIP failover, cross-region cert SANs, custom CNI routing) outweighs what we'd gain.
- A real L2 backbone (vRack) makes a single stretched cluster simpler than three meshed ones.

### Single cluster but flat / no vRack

Three workers and CPs on public-IP-only WireGuard/Tailscale, no L2. **Rejected** because:

- MetalLB L2 doesn't work without an L2 backbone — would force BGP mode + an upstream BGP-speaking router, or a NodePort/`hostNetwork` hack.
- Tailscale subnet routing for *every* intra-cluster packet would put all east-west traffic through the tailnet — fine in small clusters but a real performance hit for vmcluster-style replication.

### Ingress LB options

Getting a public IP to route into a self-managed cluster with **bare-metal workers** behind a vRack was the hardest part. Three options, in the order we tried them:

**1. MetalLB L2 + an OVH Additional IP — rejected.** The public IP was a routed Additional `/30` announced by MetalLB, with Envoy as the LoadBalancer. Proven unworkable by packet capture: inbound reaches the Envoy node over the vRack and is DNAT'd to a local pod, but the reply is routed by **destination** → the node's default route (public NIC) → it egresses sourced from the Additional IP, which OVH's per-NIC anti-spoofing drops. Source-based routing can't fix it — with DNAT the reply's source is still the *pod IP* at routing time; conntrack restores the Additional IP in POSTROUTING, *after* routing (verified live). The only routing fix is **connmark**, which needs nftables *mangle* rules Talos doesn't expose (a privileged DaemonSet outside Talos's model).

**2. OVH Public Cloud Load Balancer (Octavia, `ovh_cloud_project_loadbalancer`) — rejected.** It's OpenStack-native: backends must be **OpenStack-allocated** IPs (the bare-metal workers aren't), and it needs a gateway-enabled subnet. Enabling the subnet gateway **force-recreates the subnet and cascades to recreating the CP on it**, and a gateway-enabled subnet makes the private gateway the CP's default route — stranding its egress (no NTP → can't join). It fits all-OpenStack clusters (OVH *Managed* Kubernetes), not our mixed CP + bare-metal topology. (Learned the hard way — it stranded a CP mid-migration.)

**3. OVH IP Load Balancing (IPLB, `ovh_iploadbalancing`) — chosen.** The standalone managed LB. Backends are defined **by IP**, so the bare-metal workers attach directly; it owns its public IP. None of the Octavia constraints — no subnet gateway, no CP impact, no OpenStack-allocation requirement. TCP `:443` farm → worker NodePort `30443`; ~€/mo (entry tier).

We planned to attach it to the vRack and reach the *private* NodePort, but `vrackEligibility` is **`false`** — and the reason is concrete: **vRack is an offer-tier feature.** The OVH order catalog flags `iplb-lb1` (Pack 1, what we run) as `vrack: false`, while `iplb-lb2` and `iplb-dedicated` are `vrack: true`. At the GB subsidiary that's **£15.99/mo (`lb1`) vs £152.99/mo (`lb2`) per zone** — ~10× — purely to unlock vRack. So the farm targets the workers' **public IPs** instead. This works without re-introducing the MetalLB return-path bug because the worker replies from its *own* public IP, which OVH's anti-spoofing accepts. The trade-offs it pulls in — a `30443` hole on the workers' public NIC (scoped to the IPLB NAT range `10.108.0.0/14`), `kube-proxy --nodeport-addresses=0.0.0.0/0`, one Envoy per worker, and PROXY-protocol v2 for real client IPs — are covered under *Ingress* and *Public NIC lockdown*. Staying on `lb1` is deliberate: the `10.108.0.0/14` lockdown already gives LB-only ingress, so paying ~10× for `lb2`+vRack would buy only architectural tidiness (private-only backends, dropping those four workarounds), not added security.

### Tailscale on CPs only

Workers without the Tailscale extension. **Rejected** after discovering that the Talos image schematic bundles the Tailscale extension on every node — if the extension is installed but not configured, the node sits in a perpetual extension-failed state and won't become Ready. Configuring the extension on workers (with `TS_ROUTES` empty so they don't advertise) is the path of least resistance.

### Floating VIP for operator access

Originally the kubeconfig pointed all operators at the VIP. **Rejected** after demonstrating that the floating IP isn't reliably reachable from outside the vRack via Tailscale subnet routing (cross-DC ARP propagation for short-lived IPs is flaky on OVH's vRack). Now the cert SANs include all CP private IPs, and the kubeconfig is rewritten to point at a specific CP private IP for operator workflows. The VIP remains the in-cluster endpoint.

### OVH-side firewalls (Public Cloud security groups, bare-metal Network Firewall)

Considered as the public-NIC lockdown layer. **Rejected** as the primary mechanism because OVH's bare-metal Network Firewall is stateless (can drop specific ports but can't do clean default-deny + established) and the Public Cloud security groups are different again. Talos's in-host ingress firewall is stateful (nftables conntrack), uniform across CPs and workers, lives in git alongside the rest of the machine config, and works without extra terraform provider plumbing. We may add OVH-side firewalls later as a belt-and-suspenders layer (anti-DDoS at the edge), but they're not primary.

## Consequences

### Positive

- A single DC outage takes one CP or one worker offline, not the whole cluster. etcd survives with 2/3 CPs; workloads continue on the remaining 2/3 workers.
- Cost is roughly 6× small-instance pricing (3 b3-8 + 3 SYS-2 in staging) per env, vs paying per managed-K8s cluster.
- One Flux GitOps source per env, one kubeconfig, one Tailscale subnet route.
- Operators get cluster access from anywhere they have Tailscale.

### Negative

- The vRack is a hard prerequisite. Going multi-cloud or splitting away from OVH means redesigning the L2 story.
- Cross-DC RTT to SBG (~10 ms) puts workers further from CPs than they'd be in a single-DC cluster. Acceptable for kubelet ↔ apiserver but pod-to-pod traffic between DCs pays the same cost — worth keeping in mind for chatty workloads.
- The vmcluster (when we deploy it) replicates over the vRack between DCs. Bandwidth and latency are fine but per-DC retention math is harder than for a single-DC cluster.
- Ingress rides the workers' public NICs rather than the vRack (forced by `vrackEligibility: false`), so there's a `30443` firewall hole — but scoped to the IPLB's NAT range (`10.108.0.0/14`), so only the LB reaches it. If OVH ever enables vRack eligibility on IPLB, we can move ingress back onto the private network and drop the hole entirely.

### Operational implications

- **Per-env state** isolation in S3 at `yucca/o11y/v3/<module>/<env>` — no shared resources between envs other than the tailnet ACL (which is tailnet-global because Tailscale only has one ACL per tailnet).
- **Bootstrap** is sensitive to ordering: cluster comes up via public IPs (Tailscale isn't running yet), then terraform pivots to private IPs once the tailnet is healthy, then the ingress firewall closes the public NIC. The `use_public_endpoints` toggle in `talos/cluster` makes this explicit.
- **Production** carries an identical topology with `Rise-1` workers and a different private CIDR. The Talos volume name conventions, StorageClass names, Tailscale tag scheme, and Flux Kustomization layout are all env-agnostic; only sizing varies.
- **Ingress sizing differs by env.** Staging runs a **single-zone (`gra`) `lb1`** front-end — cheapest, and a single LB-zone outage is acceptable for staging. Production should run a **multi-zone `lb1`** IPLB: anycast (the same public IP announced from each zone) with a front-end + farm per zone, so ingress survives a single OVH-zone outage and matches the multi-DC cluster. Each extra zone is **+£15.99/mo** (vs ~10× to move to `lb2`), so it's cheap resilience. vRack stays out of scope at both envs unless the private-only design is later judged worth `lb2`'s ~10× cost.
