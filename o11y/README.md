# Shared Grafana dashboards

Cluster-generic dashboards every tenant used to ship in its own bundle, provided once in the `Shared` Grafana folder on both environments. Each board reads the `VictoriaMetrics Fleet` datasource and filters on a multi-select `$cluster` variable, so one copy serves every cluster in the fleet.

## How it is built

`sync-job.yaml` is a config for the [VictoriaMetrics sync-job](https://github.com/VictoriaMetrics/helm-charts/tree/master/hack/sync-job), the same tool the VictoriaMetrics chart runs in-cluster. Run in generate mode it fetches each upstream dashboard listed under `sources`, renames the cluster label, adds a `cluster=~"$cluster"` filter to selectors and `by (cluster)` to aggregations, builds the `$cluster` variable from the dashboard's `clusterMetric`, points fixed datasource references at `VictoriaMetricsFleet`, and emits `GrafanaDashboard` CRs into `manifests/dashboards.yaml`. A `yq` step then pins every datasource-type variable to the Fleet datasource, which the sync-job leaves free. The output is committed and deployed by Flux through `kubernetes/apps/base/tenants/shared/bundle.yaml`, alongside the `Shared` folder in `manifests/folder.yaml`.

```fish
mise run //:o11y:render   # refresh manifests/dashboards.yaml from upstream
mise run //:o11y:check    # fail if the committed render is stale
```

Upstream sources are pinned where the upstream moves (Cilium by release tag, Flux by commit) and tracked at `master` where the VictoriaMetrics chart does the same.

## Adding a dashboard

Add its URL under `sources`, and if the upstream board has no `cluster` variable, set `clusterMetric` for it under `dashboards` keyed by the slug of its title (`Kubernetes / Views / Pods` becomes `kubernetes-views-pods`). Run the render task, review the diff, commit. Keep the board out of the VictoriaMetrics chart's own `defaultDashboards.sources` if it is one the chart also imports, so the two do not fight over the same Grafana uid.
