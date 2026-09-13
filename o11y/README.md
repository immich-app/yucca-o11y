# Shared Grafana dashboards

Cluster-generic dashboards every tenant used to ship in its own bundle, provided once in the `Shared` Grafana folder on both environments. Each board reads the `VictoriaMetrics Fleet` datasource and filters on a multi-select `$cluster` variable, so one copy serves every cluster in the fleet.

## How it is built

`sync-job.yaml` is a config for the [VictoriaMetrics sync-job](https://github.com/VictoriaMetrics/helm-charts/tree/master/hack/sync-job), the same tool the VictoriaMetrics chart runs in-cluster. Run in generate mode it fetches each upstream dashboard listed under `sources`, renames the cluster label, adds a `cluster=~"$cluster"` filter to selectors and `by (cluster)` to aggregations, builds the `$cluster` variable from the dashboard's `clusterMetric`, points fixed datasource references at `VictoriaMetricsFleet`, and emits `GrafanaDashboard` CRs into `manifests/dashboards.yaml`. A `yq` step then pins every datasource-type variable to the Fleet datasource, which the sync-job leaves free. The output is committed and deployed by Flux through `kubernetes/apps/base/tenants/shared/bundle.yaml`, alongside the `Shared` folder in `manifests/folder.yaml`.

```fish
mise run //:o11y:render   # refresh manifests/dashboards.yaml from upstream
mise run //:o11y:check    # fail if the committed render is stale
```

Both tasks first run `o11y:vendor`, which fetches boards that need a rewrite the sync-job cannot express and writes them to `vendor/` as local sources. Today that is CloudNativePG only: upstream uses `cluster` to mean the Postgres cluster, while the fleet keeps that name under `pg_cluster` and reserves `cluster` for the Kubernetes cluster, so the vendor step renames the label and variable before the sync-job adds the fleet's `$cluster`. A cluster's CNPG series must carry `pg_cluster` for the board to list its databases; the shipping guide's identity-label section shows the relabel rule, which o11y, azad and harbor apply.

The set is everything at least two clusters run: the dotdc Kubernetes views and system boards, the kube-prometheus mixin boards (kubelet, scheduler, controller manager, proxy, API server, compute resources, networking, persistent volumes, node exporter USE method), Node Exporter Full, etcd, vmagent, Cilium and Hubble, Flux, Spegel and CloudNativePG. Windows, AIX, macOS, Prometheus, Alertmanager and Grafana-overview boards from the mixin bundle are disabled. Documents are sorted by name so re-renders diff cleanly.

Upstream sources are pinned where the upstream moves (Cilium by release tag, Flux by commit) and tracked at `master` where the VictoriaMetrics chart does the same.

## Adding a dashboard

Add its URL under `sources`, and if the upstream board has no `cluster` variable, set `clusterMetric` for it under `dashboards` keyed by the slug of its title (`Kubernetes / Views / Pods` becomes `kubernetes-views-pods`). Run the render task, review the diff, commit. Keep the board out of the VictoriaMetrics chart's own `defaultDashboards.sources` if it is one the chart also imports, so the two do not fight over the same Grafana uid.
