# Grafana dashboards and alerts

o11y's Grafana renders the dashboards and alert rules that each project ships to it. Nothing is clicked in the UI and left to rot: every dashboard and alert is a `grafana-operator` CR, delivered one of two ways, and grouped into a per-project folder.

## Folders are the project boundary

Each project gets a Grafana **folder** named for it, and both its dashboards and its alert rule groups file under that folder:

| Folder | Owner | Delivered by |
| --- | --- | --- |
| `yucca` | the yucca cluster/product | yucca's signed OCI bundle (Model A) |
| `o11y` | this cluster's own dashboards/alerts | authored in this repo (Model B) |

Add a project, add a folder. That folder is the unit you scope dashboards, alerts, and (eventually) permissions to.

## Model A: a project ships a signed OCI manifest bundle

This is how yucca ships (immich-app/yucca#315, see that repo's `o11y/README.md`). The project's CI renders each dashboard into a self-contained `GrafanaDashboard` CR (JSON embedded as `spec.gzipJson`) plus any `GrafanaAlertRuleGroup` CRs and a `GrafanaFolder`, pushes them as **one signed OCI artifact** (`flux push artifact` + cosign keyless), and o11y consumes the whole thing with a single Flux `OCIRepository` + `Kustomization`. New dashboards/alerts flow automatically on the next artifact.

o11y's consumer side lives once in `kubernetes/apps/base/yucca-o11y/` and is pulled into each env's `o11y` overlay:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: yucca-o11y, namespace: flux-system }
spec:
  interval: 1m
  url: oci://ghcr.io/immich-app/yucca/o11y-manifests
  ref:
    tag: main            # tracks every merge; no digest, or auto-updates stop
  verify:                # gate on the CI cosign signature
    provider: cosign
    matchOIDCIdentity:
      - issuer: "^https://token\\.actions\\.githubusercontent\\.com$"
        subject: "^https://github\\.com/immich-app/yucca/\\.github/workflows/o11y\\.yml@refs/(heads/main|tags/v[^@]+)$"
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata: { name: yucca-o11y, namespace: flux-system }
spec:
  interval: 10m
  sourceRef: { kind: OCIRepository, name: yucca-o11y }
  path: ./
  prune: true
  targetNamespace: o11y
  dependsOn: [{ name: grafana-operator }]
```

The bundle's CRs carry sane defaults (`instanceSelector: {dashboards: grafana}`, `folderRef: <project>`, `resyncPeriod`), so o11y applies them as-is. The GHCR package must be public (or set `secretRef` on the OCIRepository), and source-controller needs sigstore egress for `verify`.

## Model B: authored in this repo (o11y's own)

For this cluster's own dashboards and alerts, they live under `kubernetes/apps/base/grafana/` and deploy with the grafana Flux Kustomization:

- **Dashboards** - `base/grafana/dashboards/*.yaml`, one `GrafanaDashboard` per file, `folderRef: o11y`. Source the JSON however fits: `spec.url` to a raw/grafana.com dashboard (the envoy and cnpg dashboards), `spec.gzipJson`, etc. Map dashboard `__inputs` (e.g. `DS_PROMETHEUS`) to `datasourceName: VictoriaMetrics`.
- **Alerts** - `base/grafana/alerts-*.yaml`, a `GrafanaAlertRuleGroup` with `folderRef: o11y`.

## Alerting

**Contact points.** A `GrafanaContactPoint` per destination. Secrets (like a Discord webhook) come from a Secret via `receivers[].valuesFrom`, populated by an ExternalSecret from 1Password - never in git. Contact points live in the shared Grafana Postgres, so with the HA replica gossip cluster a firing alert notifies **once**, not once per replica.

**Routing.** One `GrafanaNotificationPolicy` routes by the **`project`** label - the same axis as the folders:

```yaml
route:
  receiver: discord           # default / catch-all
  routes:
    - object_matchers: [["project", "=", "yucca"]]
      receiver: discord
    - object_matchers: [["project", "=", "o11y"]]
      receiver: discord        # point at an o11y-specific contact point when one exists
```

So **every alert rule must set a `project` label** matching its folder, or it falls through to the default route.

**Alert rule anatomy.** A `GrafanaAlertRuleGroup` (`folderRef: <project>`, an `interval`) with `rules[]`; each rule is a query stage on the `VictoriaMetrics` datasource (uid `VictoriaMetrics`) feeding a `__expr__` threshold stage, plus `labels` (at least `project` + `severity`) and `annotations`. See `base/grafana/alerts-o11y.yaml` for the pattern (a heartbeat plus target-down and ingestion-stalled rules).

## If you ship metrics to this cluster and want dashboards/alerts

1. Pick a delivery model: **Model A** (recommended for a separate repo/cluster - you own a signed bundle, o11y adds one OCIRepository) or **Model B** (PR the CRs into `base/grafana`).
2. Everything you ship files under **your project's folder**; ask for one if it does not exist.
3. Label every alert rule `project: <you>` so the notification policy routes it; add a route (and, if you want your own channel, a contact point) for your project.
4. Dashboards use a `$datasource` variable and map `DS_PROMETHEUS` to `VictoriaMetrics`; alerts query the `VictoriaMetrics` datasource.

## How updates flow

- **Model A:** edit in the source repo, merge to `main` -> CI pushes the `:main` artifact (signed) -> o11y's OCIRepository picks it up within its `interval` -> Kustomization applies -> grafana-operator syncs. Roughly a minute end to end.
- **Model B:** PR the CR change here -> merge -> Flux reconciles `base/grafana`.
