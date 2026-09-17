# Runbook: VictoriaLogs VLDistributed cutover

Replaces the single sharded VictoriaLogs cluster with a two-zone `VLDistributed`, declared in the `vldistributed` block of the `victoria-metrics-k8s-stack` HelmRelease and reconciled by the VictoriaMetrics operator. Background: [#129](https://github.com/immich-app/yucca-o11y/issues/129). Architecture: [application architecture guide, VictoriaLogs](../../04-application-architecture-guide.md#victorialogs).

Staging is rehearsed live with Flux suspended and the branch applied from its own render; production is cut over by merging. Commands are fish, run from the repo root on the branch with the right kube context selected. Anything addressed as `*.svc.cluster.local` has to run from inside the cluster; everything below uses the mesh hostnames instead.

```fish
function apply_ks
    flux -n flux-system build kustomization $argv[1] --path ./kubernetes/apps/base/$argv[1]/app | kubectl apply --server-side --field-manager=kustomize-controller --force-conflicts -f -
end
```

`apply_ks` applies as Flux's own field manager on purpose, so values the branch deletes are actually removed rather than surviving as drift.

## Read this first: the blast radius moved

The log tier now lives **inside the metrics HelmRelease**. `cluster-apps` patches every HelmRelease in this repo with `RemediateOnFailure` and `retries: 2`, so a malformed `vldistributed` block does not fail in isolation: it fails the `victoria-metrics` upgrade and remediates the whole monitoring stack, metrics included, on the cluster that watches everything else.

That is the price of putting logs in the stack chart, and it is why staging is rehearsed rather than merged straight through. Render before you apply, every time.

Two consequences for how you verify:

- The HelmRelease going Ready means the **CR was accepted**, not that the zones are up. The operator builds VLClusters, VLAgents and the VMAuth afterwards. The `victoria-metrics` Kustomization does gate on this: it health-checks the `VLDistributed` through `healthCheckExprs` on `status.updateStatus`, so the Kustomization (and everything that `dependsOn` it) only goes Ready once the operator reports `operational`. During the rehearsal Flux is suspended, so check the zones yourself (A3).
- The CR is named `victoria-logs` via the chart's `vldistributed.name`. The operator names the managed VMAuth after the CR, so a CR that inherited the release's `fullnameOverride` (`victoria-metrics`) would adopt and wholesale-replace the spec of the **public metrics gateway** of that name, and with no `driftDetection` in this repo Flux would not heal it. A2 checks the name and the gateway explicitly.

## Generated names

The operator derives zone object names as `<cr-name>-<zone>`, and component workloads as `vl<component>-<zone-object-name>`:

| Thing | Name |
|---|---|
| VLDistributed CR | `victoria-logs` |
| VLCluster per zone | `victoria-logs-a`, `victoria-logs-b` |
| VLAgent per zone | `victoria-logs-a`, `victoria-logs-b` |
| Managed VMAuth | `victoria-logs` (Service `vmauth-victoria-logs:8427`) |
| Storage workloads | `vlstorage-victoria-logs-a`, `vlstorage-victoria-logs-b` |

One endpoint serves both directions: `/insert/*` is load-balanced across the zone agents, which each replicate to every zone, and `/select/*` is `first_available` across the zone selects. The scrape `job` label of each component is its Service name, so `vl_rows_ingested_total{job="vlstorage-victoria-logs-a"}` is zone A's storage (`type="internalinsert"`).

## History: no migration, old tier stays readable until retention drains

Nothing is copied into the new zones; both start empty. The old sharded cluster is **kept running read-only** as a legacy tier so existing history stays queryable while it ages out under its own retention (30d staging, 120d production), and is then removed (see [Decommission](#decommission-the-legacy-tier)):

- `kubernetes/apps/base/victoria-logs/` stays, with `vlinsert.enabled: false` so nothing can write to it; every writer already points at the new VMAuth. `vlselect` and the three `vlstorage` pods keep serving reads.
- Grafana gets a second datasource, `VictoriaLogs Legacy` (uid `VictoriaLogsLegacy`), pointing at the old `vlselect`. The default `VictoriaLogs` datasource points at the new tier, so dashboards and Explore land on new data unless someone picks Legacy on purpose.
- The `vlogs.` mesh route, `victoria-logs-mcp` and both gateways point only at the new tier. The legacy data is reachable through Grafana alone.

Copying the history across instead was a choice, not a forced move. Upstream answered this exact scenario in [VictoriaLogs#1705](https://github.com/VictoriaMetrics/VictoriaLogs/issues/1705), a sharded vlstorage cluster moving to per-zone clusters with one vlstorage each, and gave three supported options. Recorded here so the decision can be revisited knowingly:

1. **Export and re-ingest everything.** Query the old cluster's `/select/logsql/query`, which merges the shards at query time, and feed the JSONLine output to the vlagent. Split into non-overlapping time ranges and checkpoint each one: there is no dedup, so retrying a completed range duplicates it. A full-day query hits the query-duration limit, a dropped connection mid-window silently truncates, and tenant headers and stream fields have to be preserved.
2. **Keep the old storage in the read path.** Point the new per-zone `vlselect` at the old vlstorage nodes alongside its own until the old data expires by retention. No copying at all. The reporter on that issue first thought this double-counted and then corrected themselves: mapping the old storages to each new vlselect works.
3. **Copy one shard, re-ingest the rest.** Because the new storage is empty, snapshots of one old shard's per-day partitions restore into it without collision; only the remaining shards need exporting and re-ingesting. With three shards that removes about a third of the work.

What is genuinely impossible is the simple thing: merging all three shards by rsync. The old store spreads each day across three `vlstorage` pods under the same per-day partition name, and `/internal/partition/attach?name=YYYYMMDD` attaches exactly one directory per day-name, so the documented [backup and restore](https://docs.victoriametrics.com/victorialogs/#backup-and-restore) path is single-to-single only. That is what rules out the cheap path, not the options above.

The old PVCs `vlstorage-volume-victoria-logs-vlstorage-{0,1,2}` stay bound to the legacy tier for its whole life, and the old chart sets no `persistentVolumeClaimRetentionPolicy`, so even the final removal orphans them intact; they are deleted by hand as the last decommission step.

## Part A: staging rehearsal

### A0. Settings key first

The branch adds `CLUSTER_VMLOGS_SIZE`. The root `flux-system` Kustomization re-applies `cluster-settings` from `main` every 10 minutes and removes any key not in git, so it only survives while the root is suspended.

```fish
flux -n flux-system suspend kustomization flux-system
kubectl apply --server-side --force-conflicts -f kubernetes/clusters/staging/cluster-settings.yaml
kubectl -n flux-system get configmap cluster-settings -o jsonpath='{.data.CLUSTER_VMLOGS_SIZE}{"\n"}'
```

An empty result means the rendered CR gets a PVC with no size. Do not continue until it prints `200Gi`.

### A1. Suspend

```fish
for k in victoria-metrics victoria-metrics-users victoria-logs victoria-logs-collector victoria-logs-mcp grafana
    flux -n flux-system suspend kustomization $k
end
```

### A2. Apply the stack, then check the public vmauth survived

```fish
apply_ks victoria-metrics
kubectl -n o11y get vldistributed -o yaml | yq '.items[] | .metadata.name, .spec.backendType, [.spec.zones[].name]'
```

Expect exactly one CR, `victoria-logs`, `VLCluster`, `[a, b]`. A CR named `victoria-metrics` means the chart's `vldistributed.name` did not take: stop. Now the check that matters most:

```fish
kubectl -n o11y get vmauth victoria-metrics -o jsonpath='{.metadata.ownerReferences}{"\n"}'
kubectl -n o11y get vmauth victoria-metrics -o jsonpath='{.spec.httpRoute.hostnames}{"\n"}'
```

The first must be **empty** and the second must still list `vmauth.<CLUSTER_APP_DOMAIN>`. An ownerReference pointing at VLDistributed, or a missing httpRoute, means the managed VMAuth adopted the public gateway: stop and re-apply with the name fixed before anything else.

### A3. Confirm the operator built the zones

Flux is suspended, so nothing is watching `status.updateStatus` for you.

```fish
kubectl -n o11y get vldistributed victoria-logs -o jsonpath='{.status.updateStatus}{"\n"}'
kubectl -n o11y get vlcluster,vlagent,vmauth
kubectl -n o11y rollout status statefulset/vlstorage-victoria-logs-a --timeout=5m
kubectl -n o11y rollout status statefulset/vlstorage-victoria-logs-b --timeout=5m
kubectl -n o11y rollout status deployment/vmauth-victoria-logs --timeout=2m
```

`operational`, two VLClusters, two VLAgents, and the VMAuth at 2/2.

### A4. Confirm the zones are on different workers

The hostname spread is what makes the two zones independently survivable. PVCs bind on first schedule and pin the pods, so catch this before data lands. The agents matter as much as the storage: they hold node-local queue PVCs too, and the VMAuth writes only to them.

```fish
kubectl -n o11y get pod -l 'app.kubernetes.io/name in (vlstorage,vlagent)' \
  -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName
```

Two storage pods on two distinct nodes and two agent pods on two distinct nodes, or stop.

### A5. Rewire the consumers, freeze the legacy tier

```fish
apply_ks victoria-metrics-users
apply_ks victoria-logs-collector
apply_ks victoria-logs-mcp
apply_ks grafana
apply_ks victoria-logs
```

The last apply turns the old cluster read-only (`vlinsert.enabled: false` removes its vlinsert Deployment and Service) and drops its copy of the `vlogs-mesh` HTTPRoute, which `victoria-metrics-users` now owns. Confirm the freeze and that Grafana shows both datasources:

```fish
kubectl -n o11y get deploy,svc -l app.kubernetes.io/component=vlinsert
kubectl -n o11y get grafanadatasource victoria-logs victoria-logs-legacy
```

The first must return nothing; the second must show both `synchronized`. In Grafana, `VictoriaLogs` is the default and answers with fresh rows from the new zones; `VictoriaLogs Legacy` still answers a query over the last 24h from the old shards.

### A6. Verify replication

Both zones should ingest at a similar rate. The images are scratch-based with no shell, so read the scraped metrics rather than exec-ing. Scope to the storage jobs: the collector, both zone agents and both vlinserts export the same counter, and the agent rows are symmetric even when one zone's storage receives nothing.

```fish
set -x VMQ https://vmetrics.staging.o11y.futo.network/select/1:1/prometheus
curl -s "$VMQ/api/v1/query" --data-urlencode 'query=sum by (job) (rate(vl_rows_ingested_total{cluster="o11y", job=~"vlstorage-victoria-logs-.*"}[5m]))' \
  | jq -r '.data.result[] | "\(.metric.job)\t\(.value[1])"'
```

Two rows, both non-zero and within the same order of magnitude. One at zero means its agent is not delivering. Zero rows means the job labels differ from the table above; fix the alert expression in `kubernetes/apps/base/grafana/app/alerts-o11y.yaml` before merging.

```fish
curl -s "$VMQ/api/v1/query" --data-urlencode 'query=vlagent_remotewrite_packets_dropped_total{cluster="o11y"}' \
  | jq -r '.data.result[] | "\(.metric.url)\tdropped=\(.value[1])"'
```

Dropped should be flat at zero. vlagent drops blocks when a destination answers 400 or 404.

### A7. Verify read failover

Take one zone's storage away and confirm reads keep working. Zone A's vlselect will 502 without its vlstorage, and the vmauth should retry onto zone B.

```fish
set -x VLQ https://vlogs.staging.o11y.futo.network
kubectl -n o11y delete pod -l app.kubernetes.io/name=vlstorage,app.kubernetes.io/instance=victoria-logs-a --wait=false
for i in (seq 1 20)
    curl -s -o /dev/null -w '%{http_code} ' "$VLQ/select/logsql/query" --data-urlencode 'query=_time:5m | stats count()'
    sleep 2
end
echo
```

Every code must be 200. Any 502 means the vmauth is not failing over: check that the read targetRef carries `first_available` and the retry status codes, which the operator sets, and that `search.allowPartialResponse` has not been set anywhere (a partial response returns 200 with incomplete data and defeats the whole mechanism).

While zone A is down, the alert expression should read 0: `o11y-logs-ingestion-stalled` multiplies the slowest zone's rate by a "two zones reporting" gate, so a zone with no series at all trips it rather than dropping out of the minimum.

### A8. Resume

```fish
for k in grafana victoria-logs-mcp victoria-logs-collector victoria-logs victoria-metrics-users victoria-metrics flux-system
    flux -n flux-system resume kustomization $k
end
```

Resuming the root re-applies `cluster-settings` from `main`, dropping `CLUSTER_VMLOGS_SIZE` until the PR merges. Keep the window between A0 and merge short, or leave the root suspended.

## Part B: merge

One PR. External shippers are unaffected: hostname, token and path allowlists on both gateways are unchanged, only the backend URL behind the logs targetRefs moves to `vmauth-victoria-logs:8427`.

## Part C: production cutover

Merging is the production cutover, and it carries the metrics tier with it (see [blast radius](#read-this-first-the-blast-radius-moved)). Watch the `victoria-metrics` HelmRelease through the reconcile, not just the logs objects.

**Before merging, land the settings key on production by hand**, the same as A0 does on staging. The `victoria-metrics` Kustomization reconciles on the same source change that updates `cluster-settings`, and Flux substitutes an unset variable as an empty string. If it renders first, the CR carries an empty PVC size, the API server rejects it, and `RemediateOnFailure` rolls the whole metrics release back twice before parking it failed. It heals on the next render, but that is an avoidable rollback of the store that watches everything else.

```fish
flux -n flux-system suspend kustomization flux-system
kubectl apply --server-side --force-conflicts -f kubernetes/clusters/production/cluster-settings.yaml
kubectl -n flux-system get configmap cluster-settings -o jsonpath='{.data.CLUSTER_VMLOGS_SIZE}{"\n"}'
```

`500Gi`, then merge. The root stays suspended so its 10-minute re-apply of `main` cannot strip the key before the merge lands; `cluster-apps` and its children keep reconciling the new revision regardless. Once the `victoria-metrics` Kustomization is Ready on the merged revision, resume the root:

```fish
flux -n flux-system resume kustomization flux-system
```

Ordering after that is handled by Flux: `victoria-logs` depends on `victoria-metrics-users`, so both gateways are repointed at the new tier before the legacy `vlinsert` is removed, and the `vlogs-mesh` route is re-owned before the old owner prunes it.

Sizing: each zone holds a full copy, roughly 343 GB for 120 days, against `CLUSTER_VMLOGS_SIZE: 500Gi` and about 1.8 TB free per worker. OpenEBS local-hostpath does not enforce PVC size, so the number is nominal. Memory is the tighter constraint on staging's 32 GB workers; production's 128 GB workers have room.

Repeat A2, A3, A4, A6 and A7 against production, then confirm external shippers are landing:

```fish
set -x VLQ https://vlogs.o11y.futo.network
curl -s "$VLQ/select/logsql/query" --data-urlencode 'query=_time:5m | stats by (cluster) count()'
```

`spice`, `father` and `harbor-infra-prod` should all appear.

## Rollback

Revert the PR. The legacy tier is still running with its history, so the revert only re-enables its `vlinsert` and points the writers, the datasource, MCP and the mesh route back at it.

Note the coupling cuts both ways here: reverting also rolls the metrics HelmRelease. Check `vmcluster` and the public vmauth after a revert, not just the log tier.

What is lost is whatever the zones ingested during the window: the revert deletes the CR, and with it both zones and their data (`spec.retain` is unset). If that matters, set `spec.retain: true` on the CR before reverting and re-ingest from the retained zone into the old tier afterwards using option 1 under [History](#history-no-migration-old-tier-stays-readable-until-retention-drains).

## Decommission the legacy tier

The legacy tier is temporary: a couple of months, or as soon as its retention has drained, whichever the team prefers. It is empty once this returns no rows on the Legacy datasource, or via its `vlselect` from inside the cluster:

```fish
kubectl -n o11y run -it --rm vlq --image=curlimages/curl --restart=Never -- \
  curl -s http://victoria-logs-vlselect.o11y.svc.cluster.local:9471/select/logsql/query --data-urlencode 'query=* | stats count()' --data-urlencode 'limit=1'
```

One PR removes it all:

1. `kubernetes/apps/base/victoria-logs/` and its entry in both `kubernetes/apps/<env>/o11y/kustomization.yaml`.
2. `kubernetes/apps/production/o11y/patches/victoria-logs.yaml` and its `patches:` line.
3. `kubernetes/apps/base/grafana/app/datasource-victoria-logs-legacy.yaml` and its `kustomization.yaml` line. Grafana dashboards that were switched to the Legacy uid by hand break at this point; search the dashboard JSON for `VictoriaLogsLegacy` first.
4. After Flux has pruned the HelmRelease and its pods, the orphaned PVCs `vlstorage-volume-victoria-logs-vlstorage-{0,1,2}` in `o11y`, by hand.

Once the legacy tier is gone, the [Rollback](#rollback) above no longer applies: a revert would recreate an empty old cluster.

## Operating notes

**Zone upgrades are sequential and automatic.** The operator drains the zone's agent queue, removes the zone from the VMAuth read and write targets, reconciles it, waits for readiness (`readyTimeout`, default 5m), restores it, then waits `updatePause` (default 1m) before the next zone. Reads stay served by the other zone throughout. Nothing needs staggering by hand.

**You cannot fix-forward while a zone is down.** The zone sort puts a non-operational zone first, and the drain gate waits for that zone's agent queue to empty before excluding it from the LB. A down zone's queue never empties, because that is where its undelivered writes are accumulating, so the reconcile burns the full `readyTimeout` and aborts before touching the healthy zone. If you need to push a change while a zone is down, remove that zone from `spec.zones` or set its `trafficMode` first. While that is happening the `victoria-metrics` Kustomization reports not-Ready (`status.updateStatus` is `expanding` or `failed`), and its dependents hold.

**The agent queues are explicitly persistent.** `zoneCommon.vlagent.spec.storage` is set to 20Gi, which the operator divides across destinations for `-remoteWrite.maxDiskUsagePerURL`, giving each zone 10Gi. Do not drop it: with `storage` unset the operator mounts an `emptyDir`, and the buffer that covers a down zone is then lost on any agent restart.

**Versions follow the chart, like metrics.** Nothing pins the VictoriaLogs release: `clusterVersion` and the agent image come from the chart's `global.versions.logs`, the same way `vmcluster` and `vmagent` follow `global.versions.metrics`. A k8s-stack chart bump can therefore roll the log zones too (sequentially, under the gates above); read the chart's release notes for the logs version when reviewing one.

**Deleting the CR deletes the zones.** Removing the `vldistributed` block prunes both zones and their data. `spec.retain: true` and the VLCluster `vlstorage.persistentVolumeClaimRetentionPolicy` both exist and are deliberately unset today; decide whether you want them before this has data worth keeping.

## Follow-ups

- The `#207` noise cut is not implementable from this repo: vlagent's filter flags are all `-kubernetesCollector.*` and apply only to its own collection, and vmauth routes by path, so there is no content filter on the ingest path. Cutting `spice`'s volume has to happen at `spice`. Until it does, two zones means 2x on full volume.
- There is still no backup. Two zones protect against losing one node; they do not protect against a bad delete or a bug that corrupts both.
