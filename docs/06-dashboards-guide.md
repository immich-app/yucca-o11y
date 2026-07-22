# Grafana dashboards: build and deploy

Dashboards are not committed to Grafana or to this repo as provisioning files. They are authored in the [immich-app/yucca](https://github.com/immich-app/yucca) repo, built once by CI into a single OCI artifact on GHCR, and imported here by the grafana-operator. Two repos, one artifact, no manual Grafana edits that survive a pod restart.

```text
yucca repo                          GHCR                         o11y (this repo)
dashboards/*.json  --CI (oras)-->   ghcr.io/immich-app/yucca/    GrafanaDashboard CRs
                                    dashboards:latest       -->  grafana-operator --> Grafana
```

## Building the artifact (yucca repo)

Source of truth is `dashboards/*.json` in yucca. The workflow [`.github/workflows/dashboards.yml`](https://github.com/immich-app/yucca/blob/main/.github/workflows/dashboards.yml) does two jobs:

* **validate** (on every push and PR): each file must have a `uid`, a `title`, and at least one panel, and the **file name must equal `<uid>.json`**. o11y references each dashboard by that in-artifact path, so the name/uid match is load-bearing.
* **push** (on merge to `main`, not on PRs): `oras` packages every JSON as one layer of a single artifact (type `application/vnd.grafana.dashboard+json`) and pushes it to `ghcr.io/immich-app/yucca/dashboards` with three tags:

| Tag | Mutability | Purpose |
|-----|-----------|---------|
| `0.0.<run>` | immutable | pin an exact build |
| `sha-<sha>` | immutable | trace back to a commit |
| `latest` | moving | what o11y tracks by default |

The GHCR package is public, so o11y pulls it anonymously (no pull secret). Triggers are `push`/`pull_request` scoped to `dashboards/**` plus the workflow file, and `workflow_dispatch`. See yucca's [`dashboards/README.md`](https://github.com/immich-app/yucca/blob/main/dashboards/README.md) for the dashboard set and label conventions.

## Deploying on o11y (this repo)

The consumer side is the bundle in [`kubernetes/apps/base/grafana/dashboards/`](../kubernetes/apps/base/grafana/dashboards):

* `folder.yaml` - a `GrafanaFolder` named `yucca`, so all of these land in one Grafana folder.
* `yucca.yaml` - one `GrafanaDashboard` per artifact file: `folderRef: yucca`, `instanceSelector` `dashboards: grafana`, `resyncPeriod: 10m`, `oci.reference` the `:latest` tag, and `oci.path` the `<uid>.json`.
* `kustomization.yaml` - lists the two files above.

The bundle is pulled in by `base/grafana`, which both environments deploy through the `grafana` Flux Kustomization (`dependsOn: grafana-operator`, so the CRD exists first). Because we track the mutable `:latest` tag, the operator re-pulls on its `resyncPeriod` and **content changes roll out with no o11y commit**. A dormant renovate customManager (`renovate.json`) exists only to keep the pair in lockstep if a `reference:` is ever pinned to `tag@sha256:...`.

## Add or edit a dashboard, end to end

**Edit an existing dashboard** (no o11y change needed):

1. Edit it in Grafana, then export the JSON model (Share, then Export, then the dashboard JSON).
2. In yucca, save over `dashboards/<uid>.json`, keeping the same `uid` (so the file name stays `<uid>.json`).
3. Merge to `main`. CI validates and pushes; the o11y operator re-fetches within one `resyncPeriod` (~10m).

**Add a new dashboard** (needs a change in both repos):

1. In yucca: add `dashboards/<uid>.json` (file name must equal the uid), merge to `main`. CI adds it as a new layer of the artifact.
2. In o11y: add a `GrafanaDashboard` entry to [`dashboards/yucca.yaml`](../kubernetes/apps/base/grafana/dashboards/yucca.yaml) with `path: <uid>.json`, `folderRef: yucca`, and a `metadata.name` (convention `yucca-<name>`), then reconcile. The new artifact layer alone does **not** create the dashboard: each file is imported by its own `GrafanaDashboard`, one per `path`.

**Remove a dashboard**: delete its `GrafanaDashboard` entry in o11y (and the source file in yucca).

## Verify

After a reconcile, all dashboards should report synced:

```bash
kubectl get grafanadashboard -n o11y -o custom-columns=\
'NAME:.metadata.name,SYNCED:.status.conditions[0].reason'
```

`ApplySuccessful` on each means the operator pulled the artifact and pushed it into Grafana; the dashboards then appear under the **yucca** folder in the UI.

## Conventions and gotchas

* **File name equals `<uid>.json`** on both sides (CI enforces it; o11y's `oci.path` references it).
* Dashboards use a `$datasource` variable rather than a baked-in datasource UID, so they bind to whichever VictoriaMetrics datasource the operator provisions.
* Pin `oci.reference` to `tag@sha256:...` only if you want renovate-driven, commit-gated rollout instead of the `:latest` auto-resync; the customManager then tracks it.
* Michael's OTel metrics have dotted names; query them as `{__name__="http.server.request.count", ...}` in VictoriaMetrics.
