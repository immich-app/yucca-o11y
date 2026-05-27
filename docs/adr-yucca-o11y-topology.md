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

A single **OVH Additional IP** (a `/30` block routed into the vRack) is announced by **MetalLB in L2 mode** from inside the cluster. Whichever speaker is elected leader sends gratuitous ARP for the public IP on the vRack; OVH's edge router learns the MAC and forwards external traffic.

Envoy Gateway is the only thing claiming that LoadBalancer service. TLS terminates at Envoy; everything behind it is ClusterIP-only.

> **Known blocker — external ingress is not working with MetalLB on this topology.** Inbound packets reach the Envoy node over the vRack fine, but the reply is routed by destination while its source is still the pod IP (MetalLB DNAT). OVH's per-NIC anti-spoofing then drops the reply, which egresses the public NIC sourced from the Additional IP. See [Ingress return-path asymmetry](#ingress-return-path-asymmetry-metallb--ovh-additional-ip) under Alternatives for the full analysis and the two paths forward. The current leaning is the OVH managed LB.

### Operator access

The cluster's in-cluster apiserver endpoint is a Talos **floating VIP** on the private network, elected via etcd. Kubelets and other in-cluster components use it.

Operators **don't** use the VIP. Cross-DC ARP for floating IPs has proven unreliable when routed over Tailscale subnet routes, so the operator path is:

- Tailscale extension on every node (CPs advertise the env's private CIDR as a subnet route, auto-approved via tailnet ACL)
- Operator's host accepts the subnet route
- kubectl/talosctl point at a specific CP's **static private IP**, which is in the apiserver cert SANs

### Public NIC lockdown

Talos's in-host ingress firewall (`NetworkDefaultActionConfig: block` + `NetworkRuleConfig`) drops all inbound to apid (50000), trustd (50001), kube-apiserver (6443), etcd (2379–2380), and kubelet (10250) on the public NIC. Allowed source CIDRs: Tailscale CGNAT (`100.64.0.0/10`) and the vRack CIDR.

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

### OVH Load Balancer instead of MetalLB

OVH's managed LB (Pack 2) can be attached to a vRack. Originally **rejected for now** (adds €/month; MetalLB L2 with a routed Additional IP looked functionally identical), kept as the fallback "if MetalLB proves problematic." It has — see below — so this is now the leading option. The LB terminates the connection and forwards to the cluster over the vRack, so the node never sources replies from the public IP and the asymmetry disappears. Swap cost is roughly one HelmRelease delete + an OVH LB resource in `ovh/account`.

### Ingress return-path asymmetry (MetalLB + OVH Additional IP)

**This blocks external ingress today.** Proven by packet capture on a worker:

- Inbound to the LB IP (`37.59.205.21:30443`) arrives correctly on the vRack NIC (`eno2np1`), is DNAT'd by MetalLB to a local Envoy pod, which replies.
- The reply is routed by **destination** (the external client) → the node's **default route = the public NIC** → it egresses sourced from the Additional IP. OVH's per-NIC anti-spoofing drops it (that IP isn't valid on the public NIC). The client never sees the SYN-ACK.

**Source-based routing does not fix this.** A rule like `from 37.59.205.20/30 lookup <table>` (Talos `RoutingRuleConfig`, supported since the routing-tables work in [#7184](https://github.com/siderolabs/talos/issues/7184)) never matches the reply: with DNAT the reply's source is still the *pod IP* at routing-decision time — conntrack restores it to the Additional IP in POSTROUTING, *after* routing. Verified live: the table-100 route + rule install cleanly, but the SYN-ACK still leaves the public NIC. (The Talos provider 0.10.1 also can't manage `RoutingRuleConfig`/`LinkConfig` — "not registered" — so they'd need a provider bump or out-of-band `talosctl`.)

Two paths forward, decision deferred:

1. **connmark return-routing (keep MetalLB).** Mark connections arriving on the vRack destined to the block, restore the conntrack mark onto the reply, and route by `fwMark` into a table whose default is the vRack gateway. The `fwMark` rule is expressible (`RoutingRuleConfig`), but the connmark set/restore needs nftables *mangle* rules Talos doesn't expose — so a privileged DaemonSet manipulating host nftables outside Talos's model. Functional but hacky and fragile across upgrades.
2. **OVH managed LB (above).** Clean, no node-routing hacks, costs €/month.

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
- One floating IP for ingress = one point of MetalLB L2 leader election to think about. If the leader CP dies, ~15 s reannounce gap.

### Operational implications

- **Per-env state** isolation in S3 at `yucca/o11y/v3/<module>/<env>` — no shared resources between envs other than the tailnet ACL (which is tailnet-global because Tailscale only has one ACL per tailnet).
- **Bootstrap** is sensitive to ordering: cluster comes up via public IPs (Tailscale isn't running yet), then terraform pivots to private IPs once the tailnet is healthy, then the ingress firewall closes the public NIC. The `use_public_endpoints` toggle in `talos/cluster` makes this explicit.
- **Production** carries an identical topology with `Rise-1` workers and a different private CIDR. The Talos volume name conventions, StorageClass names, Tailscale tag scheme, and Flux Kustomization layout are all env-agnostic; only sizing varies.
