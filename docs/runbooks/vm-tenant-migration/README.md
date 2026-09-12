# Runbook: tenant cutover

Moves a store's o11y cluster from VictoriaMetrics tenant `0` to `1:1`. Staging is rehearsed live with Flux suspended and the branch applied from its own render; production is cut over by merging, in two PRs, with no manual patching. Background and the tenant registry: [shipping guide, Tenants](../../05-shipping-metrics-guide.md#tenants).

Commands are fish. The `vmctl` image tag in the Job must match the store's VictoriaMetrics version (`helm show chart` on the k8s-stack chart pinned in the environment overlay reports it as `appVersion`).

```fish
set -x D docs/runbooks/vm-tenant-migration
set -x VMQ https://vmetrics.staging.o11y.futo.network
function apply_ks
    flux -n flux-system build kustomization $argv[1] --path ./kubernetes/apps/base/$argv[1]/app | kubectl apply --server-side --force-conflicts -f -
end
```

## Part A: staging rehearsal

Run from the repo root on the branch with the staging kube context selected. Flux stays suspended for these four Kustomizations until Part B merges, which also holds any Renovate change to them; keep the window short.

### A0. Settings keys first

Flux substitutes `${CLUSTER_VMETRICS_*}` and `${QUOTE}` from the live `cluster-settings` ConfigMap in `flux-system`, which the root `flux-system` Kustomization re-applies from `main` every 10 minutes, removing any key that is not in git. Until PR 1 has merged, the keys only survive while the root Kustomization is suspended. Suspend it, apply the branch's ConfigMap, confirm the keys, and only then render anything. The root Kustomization manages the cluster-level tree only (the child Kustomization objects and this ConfigMap); the children keep reconciling their own paths while it is suspended.

```fish
flux -n flux-system suspend kustomization flux-system
kubectl apply --server-side --force-conflicts -f kubernetes/clusters/staging/cluster-settings.yaml
kubectl -n flux-system get configmap cluster-settings -o jsonpath='{.data.CLUSTER_VMETRICS_ACCOUNT_ID}:{.data.CLUSTER_VMETRICS_PROJECT_ID} quote={.data.QUOTE}{"\n"}'
```

A substituted value that must stay a string but reads as a number to YAML, such as the MCP tenant `1:1`, is wrapped as `${QUOTE}...${QUOTE}` in the manifest; kustomize drops literal quotes before substitution, so the quotes have to arrive by substitution (see the Flux docs on substituting numbers and booleans).

### A1. Suspend Flux

```fish
flux -n flux-system suspend kustomization victoria-metrics victoria-metrics-users grafana victoria-metrics-mcp
```

### A2. Fleet datasource onto the multitenant endpoint

Must land before any writer moves, or `o11y cluster stopped reporting` fires for a day. Only the Fleet datasource is applied here; the default datasource changes in A3 together with the vmauth that serves it.

```fish
flux -n flux-system build kustomization grafana --path ./kubernetes/apps/base/grafana/app | yq 'select(.metadata.name == "victoria-metrics-fleet")' | kubectl apply --server-side --force-conflicts -f -
curl -s $VMQ/select/multitenant/prometheus/api/v1/query --data-urlencode 'query=count by (cluster) (up)' | jq -c '.data.result[] | [.metric.cluster, .value[1]]'
```

Expect the same per-cluster counts the tenant-0 path returns. Fleet dashboards in Grafana should render unchanged.

### A3. Registry, writers, tenant-scoped readers

Record the cutover time first; the backfill window ends here. A render that fails `flux build` with a YAML error, or shows an empty `:` where a tenant should be, means the settings keys are missing from the live ConfigMap (see A0).

```fish
set -x CUTOVER (date -u '+%Y-%m-%dT%H:%M:%SZ')
apply_ks victoria-metrics
apply_ks victoria-metrics-users
apply_ks grafana
apply_ks victoria-metrics-mcp
```

helm-controller upgrades the release and the operator rolls vminsert, vmagent and vmalert. Verify:

```fish
kubectl -n o11y rollout status deploy -l app.kubernetes.io/name=vminsert
kubectl -n o11y logs -l app.kubernetes.io/name=vminsert --tail=100 | rg -i relabel
curl -s $VMQ/select/1:1/prometheus/api/v1/query --data-urlencode 'query=count(up)' | jq -r '.data.result[0].value[1]'
curl -s $VMQ/select/0/prometheus/api/v1/query --data-urlencode 'query=count(up{cluster="o11y"})' | jq -r '.data.result[0].value[1]'
```

The first count grows from zero as scrapes land in `1:1`; the second falls to zero once tenant 0 stops receiving o11y's scrapes. In Grafana, the default datasource now shows only post-cutover data and the Fleet datasource still shows everything.

Expected transients, not regressions: the o11y ingestion-stalled rules show NoData for one or two scrape intervals until the first samples land in `1:1`, and every `for:`-gated rule restarts its pending timer because vmalert and Grafana now read a tenant with no prior alert state.

The Fleet datasource returns `vm_account_id` and `vm_project_id` on every series, and Grafana keeps them as alert-instance labels. When a cluster moves tenant, every Fleet-datasource alert instance for it therefore changes identity: the old instance resolves and a new one starts from Pending, so an alert that was already firing for that cluster re-notifies after its `for` duration (observed on staging: luke's node-not-ready and cilium alerts re-fired 15 and 10 minutes after luke's rules loaded). Rules aggregated `by (...)` do not carry the pseudo-labels and are unaffected. No new conditions are created; check the underlying metric if a re-fired alert looks suspicious.

### A4. Backfill history

The Job copies a cluster's history from tenant 0 through the multitenant insert path, so the registry assigns its tenant and strips the tenant labels exactly as for live data. Reverse order returns the most recent history first, so tenant-scoped dashboards heal from the seam backwards. The dates and the cluster are substituted on the way to `kubectl`; the tracked manifest keeps its placeholders. On staging it ran once per cluster whose rule pair went live in A3 as a rehearsal of the mechanics; o11y's filter also takes its cluster-less vmalert output, remotes match their cluster exactly. Production backfills only o11y, see Part C.

```fish
set -x START (date -u -d '-30 days' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null; or date -u -v-30d '+%Y-%m-%dT%H:%M:%SZ')
function backfill --argument-names cluster project cluster_re
    sd -s CUTOVER_MINUS_30D $START < $D/job-vmctl-backfill.yaml | sd -s '=CUTOVER' "=$CUTOVER" | sd -s CLUSTER_RE $cluster_re | sd -s PROJECT $project | sd -s CLUSTER $cluster | kubectl apply -f -
end
backfill o11y o11y 'o11y|'
backfill luke yucca luke
backfill harbor-infra-staging harbor harbor-infra-staging
backfill fmeet-serverless fmeet serverless
kubectl -n o11y logs -f job/vmctl-backfill-o11y
```

Spot-check a point a week back on both tenants; the counts should match:

```fish
set -x T (date -u -d '-7 days' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null; or date -u -v-7d '+%Y-%m-%dT%H:%M:%SZ')
curl -s $VMQ/select/0/prometheus/api/v1/query --data-urlencode 'query=count(up{cluster="o11y"})' --data-urlencode "time=$T" | jq -r '.data.result[0].value[1]'
curl -s $VMQ/select/1:1/prometheus/api/v1/query --data-urlencode 'query=count(up)' --data-urlencode "time=$T" | jq -r '.data.result[0].value[1]'
```

Duplicates from the replicated source are handled by the existing 20s dedup on vmselect. If a chunk is too large, narrow it with `--vm-native-step-interval=hour` rather than changing vmselect flags.

### A5. Remove the tenant-0 copy

Until this step the Fleet datasource sees each migrated cluster's history twice, once per tenant, so `sum` and `count` panels and `count by (cluster) (up offset 1d)` double over the backfilled window. Once the spot-checks pass, delete the migrated series from tenant 0. Deletion is irreversible and is cleaned up during background merges; queries stop returning the series immediately.

vmselect refuses a single call that touches more than `-search.maxDeleteSeries` series (default 1,000,000; verify with the binary's `--help`), and a cluster's 30-day copy is typically several million unique series, so split each cluster's delete by metric-name prefix. The six groups below partition every possible name; on staging the largest group was about 760k series. Every call must return `204`; a refusal prints vmselect's message and means that group needs a finer split. Deletes are idempotent, so re-running is safe.

```fish
set -l chunks 'a.*' 'c.*' '[bd-j].*' '[k-o].*' '[p-z].*' '[^a-z].*'
for base in 'project="o11y",cluster=~"o11y|"' 'project="yucca",cluster="luke"' 'project="harbor",cluster="harbor-infra-staging"' 'project="fmeet",cluster="serverless"'
    for re in $chunks
        set -l m "{$base,__name__=~\"$re\"}"
        printf '%-72s ' $m
        curl -s -X POST "$VMQ/delete/0/prometheus/api/v1/admin/tsdb/delete_series" --data-urlencode "match[]=$m" -w ' %{http_code}\n'
    end
end
curl -s $VMQ/select/multitenant/prometheus/api/v1/query --data-urlencode 'query=count by (vm_account_id, vm_project_id, cluster) (up offset 1d)' | jq -c '.data.result[] | [.metric.vm_account_id + ":" + .metric.vm_project_id, .metric.cluster, .value[1]]'
```

Expect yesterday's `up` listed once per cluster under its own tenant and no `0:0` rows.

### A6. Post-cutover checks

- Grafana alert list: `o11y cluster stopped reporting` not pending; the o11y ingestion rules back to Normal.
- No tenant pseudo-labels stored in `1:1` (expect `0`; anything else means a writer bypassed the multitenant path):

  ```fish
  curl -s $VMQ/select/1:1/prometheus/api/v1/query --data-urlencode 'query=count({vm_account_id!=""})' | jq -r '.data.result[0].value[1] // 0'
  ```

- vmui on `vmetrics.<mesh>` redirects to the multitenant path and shows every cluster.
- The read-back recipe in the shipping guide, `/select/0/` on `vmauth.<mesh>`, returns o11y's series: that path now rewrites to multitenant.
- victoria-metrics-mcp answers with o11y data; it reads tenant `1:1` by default and lists the others via its `tenants` tool.

### A7. Remote shippers unchanged

Nothing on a remote changes in this cutover, whether or not its rule pair went live, and the store holds the evidence. Probe by `project` as well as by `up`: a serverless pusher such as fmeet never emits `up` and ships intermittently, so an `up`-only sweep misses it. every remote ships its own vmagent remote-write counters, so shipper health is readable from here without touching the remote. Take the baseline before A1 and compare after A3.

```fish
curl -s $VMQ/select/multitenant/prometheus/api/v1/query --data-urlencode 'query=time() - max by (cluster) (timestamp(up))' | jq -c '.data.result[] | [.metric.cluster, .value[1]]'
curl -s $VMQ/select/0/prometheus/api/v1/query --data-urlencode 'query=count by (cluster) (up{cluster!="o11y"})' | jq -c '.data.result[] | [.metric.cluster, .value[1]]'
curl -s $VMQ/select/multitenant/prometheus/api/v1/query --data-urlencode 'query=sum by (cluster) (rate(vmagent_remotewrite_requests_total{status_code!~"2.."}[10m])) + sum by (cluster) (rate(vmagent_remotewrite_retries_count_total[10m])) + sum by (cluster) (rate(vmagent_remotewrite_packets_dropped_total[10m]))' | jq -c '.data.result[] | [.metric.cluster, .value[1]]'
curl -s $VMQ/select/1:1/prometheus/api/v1/query --data-urlencode 'query=sum by (job) (increase({__name__=~"vmauth_(user|unauthorized_user)_request_backend_errors_total"}[10m]))' | jq -c '.data.result[] | [.metric.job, .value[1]]'
```

Expected: staleness of a few seconds for every remote, the same per-cluster counts as before with each remote in its own tenant or still in tenant 0 according to the registry, zero non-2xx, retries and drops on the remotes' own remote-write counters, and no growth in vmauth backend errors on either the public or the mesh gateway. The `o11y cluster stopped reporting` rule stays quiet for every remote. The read-back recipe in the shipping guide, `/select/0/` on either gateway, returns the remotes' series because that path now rewrites to multitenant.

## Part B: commit as two PRs

The branch splits into a behaviour-preserving PR and the cutover PR, so production never has the fleet view and the writers change in the same reconcile. Production's grafana Kustomization does not depend on victoria-metrics, so a single merge would leave their order to chance.

**PR 1, multitenant plumbing, a no-op while everything is in tenant 0.** The `CLUSTER_VMETRICS_*` and `QUOTE` settings keys in both environments, so the live ConfigMap carries them before any render needs them (a child Kustomization can reconcile a new revision before the root has updated the ConfigMap, which renders empty IDs once); the Fleet datasource and the vmui redirect onto `/select/multitenant`; the shared-token VMUser and the mesh-unauth VMAuth rewrites of `/insert/0/` and `/select/0/` onto multitenant; the vmagent and vmalert `remoteWrite` URLs onto `/insert/multitenant/`. Without registry rules the multitenant path stores everything in tenant 0 and multitenant reads return it, so nothing observable changes.

**PR 2, the cutover.** The relabel ConfigMap and its kustomization entry; the vminsert `configMaps` and `relabelConfig` args; vmalert `datasource` and `remoteRead`; the self-select VMAuth path; the default Grafana datasource URL; the MCP `VM_DEFAULT_TENANT_ID`; the removed `extra_label` fences; docs and this runbook.

Before opening either PR, confirm the committed render matches what is live on staging:

```fish
for ks in victoria-metrics victoria-metrics-users grafana victoria-metrics-mcp
    flux -n flux-system diff kustomization $ks --path ./kubernetes/apps/base/$ks/app
end
```

Every diff should be empty. Resume the root Kustomization once PR 1 has merged, since the settings keys then come from git. Resume the four app Kustomizations only after PR 2 has merged; resuming them earlier reverts the cutover on staging.

```fish
flux -n flux-system resume kustomization flux-system
# after PR 2:
flux -n flux-system resume kustomization victoria-metrics victoria-metrics-users grafana victoria-metrics-mcp
```

## Part C: production cutover

Merging PR 2 is the production cutover: Flux moves o11y's writers, registry and readers together. Only o11y is backfilled on production, and only 30 days: it is the one cluster with tenant-scoped readers (the default Grafana datasource, vmalert's remoteRead and MCP, all pinned to `1:1`), and a month covers what operational dashboards look at. Older o11y history stays in tenant 0, visible through the Fleet datasource, until the 120-day retention expires it. Staging measured this at about four hours for 30 days of o11y; run it off-peak.

```fish
set -x VMQ https://vmetrics.o11y.futo.network
set -x CUTOVER <merge reconcile time, UTC RFC3339>
set -x START (date -u -d '-30 days' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null; or date -u -v-30d '+%Y-%m-%dT%H:%M:%SZ')
backfill o11y o11y 'o11y|'
```

Then A5 for o11y only, the six chunked deletes of `{project="o11y",cluster=~"o11y|"}` from tenant 0, and A6.

Remotes are not backfilled on production. Expect each remote's already-firing Fleet-datasource alerts to resolve and re-fire once when its rule pair lands (see A3); move remotes at a quiet time or tell the project beforehand. Nothing reads a remote through a tenant-scoped path: the Fleet datasource reads the multitenant endpoint, which returns tenant 0 and the new tenant as one continuous view, so a remote's history simply ages out of tenant 0. Moving a remote is therefore a registry-only change: add its rule pair to the ConfigMap in its own PR, confirm its `vm_project_id` appears on the Fleet datasource, and that is all. Disk is not a constraint either way: production vmstorage nodes run at about 9% of 1.8 TiB each.

## Rollback

On staging, `flux resume` before PR 2 merges reverts every object to tenant 0, including removal of the relabel rules. Do that first. Only then copy `1:1` back if needed, with the Job's source and destination swapped to `/select/1:1/prometheus` and `/insert/0/prometheus`; with the rules gone, nothing re-stamps the copied samples. On production, revert PR 2 and follow the same copy-back.
