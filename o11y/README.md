# Shared Grafana dashboards

Cluster-generic dashboards every tenant used to ship in its own bundle, provided once in the `Shared` Grafana folder on both environments. Each board reads the `VictoriaMetrics Fleet` datasource and filters on a multi-select `$cluster` variable, so one copy serves every cluster in the fleet.

## How it is built

`sync-job.yaml` is a config for the [VictoriaMetrics sync-job](https://github.com/VictoriaMetrics/helm-charts/tree/master/hack/sync-job), the same tool the VictoriaMetrics chart runs in-cluster. Run in generate mode it fetches each upstream dashboard listed under `sources`, renames the cluster label, adds a `cluster=~"$cluster"` filter to selectors and `by (cluster)` to aggregations, builds the `$cluster` variable from the dashboard's `clusterMetric`, points fixed datasource references at `VictoriaMetricsFleet`, and emits `GrafanaDashboard` CRs into `manifests/dashboards.yaml`. A `yq` step then pins every datasource-type variable to the Fleet datasource, which the sync-job leaves free. Nothing generated is committed: `manifests/dashboards.yaml` and `vendor/` are git-ignored. `.github/workflows/o11y.yml` runs the same mise tasks in CI: pull requests render and `kustomize build` the bundle, and every push to `main` that touches `o11y/` renders again and publishes `manifests/` as the signed OCI artifact `ghcr.io/immich-app/yucca-o11y/o11y-manifests:main` (`flux push artifact` plus keyless cosign), the same shape and naming the tenant bundles use. Upstream changes reach the clusters on the next publish, so re-run the workflow by hand to pick them up without a config change. The central cluster consumes it through `kubernetes/apps/base/tenants/shared/bundle.yaml`, alongside the `Shared` folder in `manifests/folder.yaml`.

```fish
mise run //:o11y:render   # render manifests/dashboards.yaml locally for review (git-ignored)
```

Both tasks first run `o11y:vendor`, which fetches boards that need a rewrite the sync-job cannot express and writes them to `vendor/` as local sources. Today that is CloudNativePG only: upstream uses `cluster` to mean the Postgres cluster, while the fleet keeps that name under `pg_cluster` and reserves `cluster` for the Kubernetes cluster, so the vendor step renames the label and variable before the sync-job adds the fleet's `$cluster`. A cluster's CNPG series must carry `pg_cluster` for the board to list its databases; the shipping guide's identity-label section shows the relabel rule, which o11y, azad and harbor apply.

The set is everything at least two clusters run: the dotdc Kubernetes views and system boards, the kube-prometheus mixin boards (kubelet, scheduler, controller manager, proxy, API server, compute resources, networking, persistent volumes, node exporter USE method), Node Exporter Full, etcd, vmagent, Cilium and Hubble, Flux, Spegel, Envoy Gateway and CloudNativePG. Windows, AIX, macOS, Prometheus, Alertmanager and Grafana-overview boards from the mixin bundle are disabled. Documents are sorted by name so an unchanged upstream renders byte-identical and the published artifact keeps its digest.

Upstream sources are pinned where the upstream moves (Cilium by release tag, Flux by commit) and tracked at `master` where the VictoriaMetrics chart does the same.

## Adding a dashboard

Add its URL under `sources`, and if the upstream board has no `cluster` variable, set `clusterMetric` for it under `dashboards` keyed by the slug of its title (`Kubernetes / Views / Pods` becomes `kubernetes-views-pods`). Run the render task and review the output locally, then commit the config change; CI renders and publishes. Keep the board out of the VictoriaMetrics chart's own `defaultDashboards.sources` if it is one the chart also imports, so the two do not fight over the same Grafana uid.
