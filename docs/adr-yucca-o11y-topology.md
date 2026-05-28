# ADR: Yucca O11y cluster topology

* **Date:** 2026-04-14
* **Status:** Accepted (see [Decision](./decision-yucca-o11y-topology.md))
* **Authors:** Devin
* **Stakeholders:** O11y team, E2EE Backup team

## Context

We are building a centralized observability platform for all FUTO services, starting with the E2EE Backups product. The platform must serve multiple teams (Backups, Grayjay, future projects) with metrics, logs, traces, dashboards, and alerting on a shared infrastructure. This ADR evaluates three architectural options for the cluster topology going forward.

## Decision drivers

* **99.99% uptime target** — 52 minutes downtime/year
* **Production budget of ~$1,000/month** (revised upward from original $500/month target due to OVH pricing increases)
* **Complete isolation from production infrastructure** — separate DNS, hosting, network
* **Multiple geographically separate locations** — 3 distinct locations
* **Team of 3–4 engineers shared with the E2EE Backup project**
* **Meta-monitoring via Phare (or TBD)** — `<2 minute` detection of platform failures
* **Rapid team onboarding** — templated configurations, standardized integrations

> Pricing throughout is from OVH's GB subsidiary (which bills in GBP). USD figures are converted at **~£1 = $1.27** for budget comparison against the $1,000/month target.

## Option A: multi-zone multi-cluster

3 independent Kubernetes clusters, one per region (LON, RBX, FRA), each with their own control plane and workers. Cross-zone replication via VMAgent triple-write over Tailscale. Up to 9 nodes per environment.

### Pros

* Survives a full datacenter outage — data exists in all 3 zones, 2 zones continue operating if one fails
* Maximum geographic isolation — 3 fully independent failure domains

### Cons

* **Cross-zone alert deduplication required.** Per-zone vmalert fires 3 alerts per incident. Needs a global Alertmanager mesh, a global vmalert with cross-DC query latency, or a separate stateful deduplication service.
* **Grafana state diverges across zones.** Each zone runs independent Grafana with its own PVC. Requires cross-zone Postgres, LB session affinity, or a full dashboard-as-code pipeline.
* **Per-service replication scales with every new service.** VMLogs, VMTraces, and every future stateful service each need their own cross-zone write replication and VMAuth routing — the opposite of "templated configurations for rapid onboarding."
* **Tailscale becomes a critical data-plane dependency.** Cross-zone writes depend entirely on Tailscale. Ephemeral key expiry or coordination server issues silently break replication.
* **50% more infrastructure at ~33% utilization.** 9 nodes per env vs 6, with 3 independent etcd clusters, K8s upgrade cycles, and Flux reconciliation loops.
* **Exceeds the budget.** 9 bare-metal servers per environment significantly exceeds ~$1,000/month.
* **Shared team capacity.** 3–4 engineers must build and maintain all of the above before the platform delivers core value.

## Option B: single-region single-cluster

1 Kubernetes cluster in one OVH region (e.g. RBX), 3 CP + 3 workers. VictoriaMetrics in cluster mode with replicationFactor=2. vmbackup to object storage in a second region for DR.

### Pros

* Simplest operational model — one etcd cluster, one Flux instance, one upgrade cycle
* Alertmanager gossip, Grafana state, and every new service work natively with no cross-zone engineering
* Replicated storage (Longhorn, Rook-Ceph) viable — sub-millisecond intra-DC latency
* 6 nodes at close to full utilization — fits within budget
* All existing engineering transfers directly

### Cons

* Does not survive a regional outage — cold failover (vmrestore, Flux reconcile, DNS switch) could take 30–45 minutes, consuming most of the 52-minute annual budget in a single event.
* 99.99% depends entirely on a single region's availability

## Option C: stretched single-cluster across nearby regions

1 Kubernetes cluster stretched across nearby OVH DCs. Control plane nodes spread across 3 DCs for etcd quorum. Workers distributed with topology spread constraints.

### Pros

* Survives a full DC outage — etcd maintains quorum with 2/3 CP nodes, pods reschedule to surviving DCs
* Single-cluster operations — same simplicity as Option B with the geographic resilience of Option A
* 6 nodes per env — same cost as Option B
* Meets the brief's geographic distribution requirement directly
* All existing engineering transfers directly

### Cons

* **No replicated block storage across DCs.** Longhorn/Rook-Ceph are not designed for 2–10ms inter-DC RTT. Storage is node-local (OpenEBS hostpath). Acceptable for this platform's workloads since VictoriaMetrics handles replication at the application level, but limits future use cases.
* **Application-level replication adds latency.** VMCluster writes to vmstorage nodes across DCs — each write pays ~2–5ms inter-DC latency. Acceptable for metrics, worth monitoring.
* **etcd latency at the boundary.** etcd recommends `<10ms` RTT. Viable DC combinations stay under 10ms but with less headroom than a single-region cluster.
* **Network partitions more likely than intra-DC.** A partition isolating one CP node could cause brief API server unavailability during etcd re-election.

### Inter-DC latency (OVH SmokePing)

| Pair | RTT | Source |
|------|-----|--------|
| RBX ↔ GRA | ~1.9ms | [RBX → GRA](http://rbx.smokeping.ovh.net/smokeping?target=OVH.DCs.LIL2-GRA-V4) |
| RBX ↔ PAR | ~4.0ms | [RBX → PAR](http://rbx.smokeping.ovh.net/smokeping?target=OVH.DCs.PAR3-CCH01-V4) |
| PAR ↔ GRA | ~5.1ms | [PAR → GRA](https://par3-ieb01.smokeping.ovh.net/smokeping?target=OVH.DCs.LIL2-GRA-V4) |
| RBX ↔ SBG | ~9.8ms | [RBX → SBG](http://rbx.smokeping.ovh.net/smokeping?target=OVH.DCs.SXB1-SBG-V4) |
| GRA ↔ SBG | ~10.4ms | [GRA → SBG](https://lil2-gra.smokeping.ovh.net/smokeping?target=OVH.DCs.SXB1-SBG-V4) |

Direct DC-to-DC ICMP measurements. Real-world etcd consensus latency under load may be higher.

### Viable DC combinations for etcd (under 10ms worst pair)

| Combination | Worst pair RTT | Verdict |
|-------------|----------------|---------|
| **RBX + GRA + PAR** | ~5.1ms (PAR ↔ GRA) | **Best option** — all pairs well under 10ms |
| RBX + PAR + SBG | ~9.8ms (RBX ↔ SBG) | Borderline — no headroom for jitter |
| RBX + GRA + SBG | ~10.4ms (GRA ↔ SBG) | Not viable — exceeds etcd limit |

---

**Outcome:** Option C selected. See [Decision: Yucca O11y cluster topology](./decision-yucca-o11y-topology.md) for the chosen sizing, networking, and budget; see [Infrastructure: Yucca O11y cluster](./infrastructure-yucca-o11y-topology.md) for the concrete deployed configuration.
