# Grafana dashboards and alerts

o11y's Grafana renders the dashboards and alert rules that each project ships to it. Nothing is clicked in the UI and left to rot: every dashboard and alert is a `grafana-operator` CR, delivered one of two ways, and grouped into a per-project folder.

## Folders are the project boundary

Each project gets a Grafana **folder** named for it, and both its dashboards and its alert rule groups file under that folder:

| Folder | Owner | Delivered by |
| --- | --- | --- |
| `yucca` | the yucca cluster/product | yucca's signed OCI bundle (Model A) |
| `o11y` | this cluster's own dashboards/alerts | authored in this repo (Model B) |
| `harbor` | the Harbor clusters (harbor-infra-prod/staging) | harbor-o11y's key-signed OCI bundle (Model A, anonymous-pull registry) |
| `fip` | the FUTO internal platform cluster (azad) | futo-internal-platform's signed OCI bundle (Model A) |
| `version` | the Immich version worker (Cloudflare) | immich-app/version's signed OCI bundle (Model A), including recording rules |
| `fmeet` | the fmeet serverless workers (Cloudflare) | fmeet's unsigned OCI bundle (Model A, private gitlab.futo.org registry pulled with a deploy token) |
| `bootstrap` | the bootstrap DOKS cluster (palpatine) | bootstrap's key-signed GitLab OCI bundle (Model A, anonymous-pull registry: infra/bootstrap is a public project) |

Add a project, add a folder. That folder is the unit you scope dashboards, alerts, and (eventually) permissions to.

## Tags cut across folders

A folder files a dashboard under exactly one project; a **tag** is the orthogonal axis - signal type (`metrics`, `logs`), layer (`infra`, `k8s`, `app`) - that Grafana's dashboard browser filters on across every folder at once. Grafana stores tags inside the dashboard JSON model and `grafana-operator` exposes no field to inject them, so tags can only be set where the JSON is authored:

- **Bundle (Model A) and first-party (Model B) dashboards you write:** set `tags` in the dashboard JSON before shipping. Folder is your project; tags are the signal/layer cross-cut.
- **Dashboards pulled from grafana.com or a raw URL** (`spec.grafanaCom` / `spec.url`, e.g. the grafana-operator dashboard): they carry whatever tags upstream set. o11y cannot add or normalize them without vendoring the JSON inline, which forfeits the live reference and `resyncPeriod` auto-updates - so leave them as-is.

## Model A: a project ships a signed OCI manifest bundle

This is how yucca ships (immich-app/yucca#315, see that repo's `o11y/README.md`). The project's CI renders each dashboard into a self-contained `GrafanaDashboard` CR (JSON embedded as `spec.gzipJson`) plus any `GrafanaAlertRuleGroup` CRs and a `GrafanaFolder`, pushes them as **one signed OCI artifact** (`flux push artifact` + cosign keyless), and o11y consumes the whole thing with a single Flux `OCIRepository` + `Kustomization`. New dashboards/alerts flow automatically on the next artifact.

o11y's consumer side lives once in `kubernetes/apps/base/tenants/yucca/bundle.yaml`, one file per tenant listed by `base/tenants/kustomization.yaml`, which each env's `o11y` overlay pulls in. A bundle applies with kustomize-controller's own cluster-wide rights (no `serviceAccountName`), and the signature check pins it to its repo's workflow; this is accepted while each bundle repo's writers are also yucca-o11y's:

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

### Model A from a private registry

yucca's bundle is a public GHCR package, so its `OCIRepository` needs no
credential. A private project publishing to its own forge — fmeet ships to
`gitlab.futo.org:5050`, where its private GitLab project lives — has a private
registry, and there is no way around it: GitLab's
`container_registry_access_level` takes only `disabled` / `private` / `enabled`,
where `enabled` still means "everyone **with access**". Of all the project
feature access levels, only `pages_access_level` accepts `public`, so a private
project cannot expose a publicly-pullable registry. An anonymous pull scope is
refused at `/jwt/auth` outright. A public project's registry is the opposite
case, covered at the end of this section.

Two additions, then:

- **A read-only pull credential.** A GitLab *project deploy token* scoped to
  `read_registry` is the least it can be — pull on that one project's registry,
  nothing else, revocable without touching an account. Its username and password
  go into 1Password as **two separate manual secrets**, each holding its value in
  the item's `password` field — the manual-secrets module only creates
  password-category items, so a two-part credential is split rather than packed
  into extra fields on one item.
- **An ExternalSecret rendering it as a `dockerconfigjson`**, in `flux-system`,
  because that is where the `OCIRepository` lives and a `secretRef` resolves in
  its own namespace. It pulls the two items by name and templates the docker
  config around them. See the `ExternalSecret` in `base/tenants/fmeet/bundle.yaml`.

Both items go in the global `o11y_tf` vault, read through the `onepassword`
store. Not `shared_tf` — that is for credentials more than one project
consumes, and this cluster is the only thing that pulls the bundle; and not a
per-environment o11y vault, because there is one fmeet project registry and so
one token, the same in every environment. They are declared in core-infra-tf's
`o11y-manual-secrets` module and filled in by hand in `o11y_tf_manual`.

That `onepassword` ClusterSecretStore is added here: the cluster reached
`shared_tf` and the per-environment o11y vaults, but nothing had yet needed the
global o11y one, whose other items are all consumed by terragrunt rather than
from inside the cluster.

The one detail that bites: the key under `auths` must match the
`OCIRepository`'s pull host **exactly**, port and all
(`gitlab.futo.org:5050`, not `gitlab.futo.org`). A mismatch surfaces as an
authentication failure rather than as anything pointing at the cause.

An anonymously pullable registry sidesteps all of this, so the
`OCIRepository` needs no `secretRef`. harbor-o11y does this: its bundle lives
at `registry.futo.org/harbor/o11y-manifests`, where `harbor/` allows
anonymous reads. So does bootstrap on `gitlab.futo.org` itself:
`infra/bootstrap` is a public project, so `/jwt/auth` grants an anonymous pull on
`gitlab.futo.org:5050/infra/bootstrap/o11y-manifests` and no deploy token is
needed.

`verify:` is also omitted for such a bundle unless the publisher signs with a
key pair, as harbor-o11y and bootstrap do. harbor-o11y's CI signs the digest
with a key its infrastructure terraform mints, the public half is committed in
that repo as `cosign.pub`, and `base/tenants/harbor` carries it as the
`harbor-o11y-cosign` Secret referenced from `verify.secretRef`. bootstrap's
key pair is generated by hand (private half in its `futo_bootstrap_tf` vault,
public half in its `o11y/cosign.pub`), and `base/tenants/bootstrap` carries it
as `bootstrap-o11y-cosign`. Keyless cosign mints its certificate from public
Fulcio against the CI's OIDC identity, and Fulcio accepts `gitlab.com` but not
a self-hosted forge — so the keyless block above cannot simply be copied across.

### Recording rules in a bundle

A bundle may also ship `VMRule`s when its project records its own series, as immich-app/version does. o11y's `vmalert` reads only o11y's tenant and writes under o11y's identity labels, so it must not evaluate them. The setup has three parts:

- **The tenant's Kustomization** in `base/tenants/<tenant>/bundle.yaml` sets `commonMetadata.labels` `o11y.futo.org/tenant: <tenant>` on everything it applies. Flux overrides any value the bundle sets for that key, so a bundle cannot claim another tenant's label. Like the other bundles it depends only on `grafana-operator`. The `VMRule` CRD comes from `victoria-metrics` and is always installed once the cluster is up; on a fresh bootstrap the bundle fails its dry-run until then and Flux retries it.
- **o11y's own `vmalert`** (`base/victoria-metrics/app/helmrelease.yaml`) selects every `VMRule` without that label.
- **The tenant's `VMAlert`** (`base/victoria-metrics-users/app/vmalert-<tenant>.yaml`) selects the label in the `o11y` namespace and also matches `kustomize.toolkit.fluxcd.io/name: <tenant>-o11y`, which kustomize-controller sets on every object it applies, so no other bundle can feed it rules. It reads `/select/<tenant>/prometheus`, writes through the multitenant insert endpoint, and sets the tenant's identity labels as `externalLabels`, which route the results back into the tenant.

Those `externalLabels` do not pin the tenant. They displace a same-named label that comes from the query result, which `vmalert` keeps as `exported_<name>`, but a group's or rule's own `labels:` override them. A rule that set `project` or `cluster` would be filed under another tenant, so a bundle must not set identity labels (`project`, `cluster`, `env`, `provider`, `region`, `vm_account_id`, `vm_project_id`) on its groups or rules. o11y does not enforce this; immich-app/version's render script rejects them before it publishes.

Per-group `tenant` on a `VMRule` is VictoriaMetrics Enterprise only, so each tenant with rules gets its own `vmalert`. A rule that joins a recorded series with an aggregate must match on the aggregate's labels (`and on(client_ip)`), because the recorded series carries the external labels and the aggregate does not.

## Model B: authored in this repo (o11y's own)

For this cluster's own dashboards and alerts, they live under `kubernetes/apps/base/grafana/app/` and deploy with the grafana Flux Kustomization:

- **Dashboards** - `base/grafana/app/dashboards.yaml`, a single file holding the `o11y` `GrafanaFolder` and one `GrafanaDashboard` document per dashboard, `folderRef: o11y`. Source the JSON however fits: `spec.grafanaCom` or `spec.url` to a grafana.com or raw dashboard (the grafana-operator dashboard), `spec.gzipJson`, etc. Map dashboard `__inputs` (e.g. `DS_PROMETHEUS`) to `datasourceName: VictoriaMetrics`, which serves o11y's own tenant.
- **Alerts** - `base/grafana/app/alerts-*.yaml`, a `GrafanaAlertRuleGroup` with `folderRef: o11y`.

Another project's CRs authored here read its data from another tenant, so they use the Fleet datasource like a bundle does (see Datasources and tenants).

## Shared dashboards

Cluster-generic boards (Kubernetes views and system, node exporter, vmagent, Cilium, Flux, Envoy Gateway, CloudNativePG) live once in the **`Shared`** folder rather than in every tenant bundle. They are rendered from their upstream sources by the VictoriaMetrics sync-job in generate mode, filtered on a multi-select `$cluster` variable and pinned to the `VictoriaMetrics Fleet` datasource, so one copy serves every cluster; see [`o11y/README.md`](../o11y/README.md) for how to add one. A tenant bundle should not ship its own copy of a board that exists in `Shared`.

## Alerting

**Contact points.** A `GrafanaContactPoint` per destination. Alerts go to [Rootly](https://rootly.com): one webhook contact point per project (`rootly-<project>` in `base/grafana/app/contactpoint-rootly-alerts.yaml`), each posting to that project's Rootly alert source with the source's own secret, plus `rootly-heartbeat` for the dead man's switch. The alert sources, per-project services and their credentials are managed by the `deployment/modules/rootly/cluster` Terraform module, which writes each source's webhook URL into the env 1Password vault as `ROOTLY_ALERTS_<PROJECT>_URL`; the secret rides in that URL's `secret` query parameter because Rootly's Grafana endpoint reads it nowhere else. An ExternalSecret materializes it into the Secret the contact point reads via `receivers[].valuesFrom` - never in git. A resolved Grafana notification resolves the Rootly alert, and repeat notifications for a group that is still firing fold into its open Rootly alert by Grafana's group key, so each group posts to Zulip once when it fires and once when it resolves. Until escalation policies page someone, a high-urgency alert that stays open and unacknowledged also gets a daily reminder in its topic. The Rootly alert description is Grafana's notification message, rendered by the `rootly.message` template in `base/grafana/app/notificationtemplate-rootly.yaml`: each firing alert's `summary` and `description` annotations, then links to its rule, its dashboard and runbook when set, and a silence, for up to five alerts per group. Fired posts and reminders in Zulip carry that description under the title line. Rootly derives alert urgency from the `severity` label (`critical` -> High, `warning` -> Medium, otherwise Low) and, until escalation policies exist, forwards fired and resolved alerts from its own cloud to Zulip, where each project's alerts land in the `yucca-alerts` channel (harbor in `harbor-alerts`) under a `<project>-<env>` topic, via Zulip's Slack-compatible incoming webhook. Contact points live in the shared Grafana Postgres, so with the HA replica gossip cluster a firing alert notifies **once**, not once per replica.

**Rootly's Grafana integration.** Besides the alert sources, Rootly has an account-level Grafana integration (Integrations > Grafana) that takes this cluster's Grafana URL and an Admin service account token; it is what lets Rootly deep-link rules and snapshot dashboards into incidents. Rootly exposes no API or Terraform surface for it, so it is installed by hand once per env. The `deployment/modules/grafana/cluster` module owns the `rootly` service account and its token and writes the token to the env vault as `ROOTLY_GRAFANA_SERVICE_ACCOUNT_TOKEN`; paste that and `https://grafana.<env domain>` into Rootly. It is a separate module from `rootly/cluster` so the latter stays plannable while Grafana is down.

**Routing.** One `GrafanaNotificationPolicy` routes by the **`project`** label first and the **`grafana_folder`** label second. `project` is the same identity label every shipper stamps on its series (see the [shipping guide](05-shipping-metrics-guide.md#labels)); an alert instance carries it when the rule sets it as a rule label or the query keeps it in its aggregation. `grafana_folder` is added by Grafana from the folder each rule files into, so rules without the label still route by their folder:

```yaml
route:
  receiver: rootly-o11y       # default / catch-all
  routes:
    - object_matchers: [["project", "=", "yucca"]]
      receiver: rootly-yucca
    - object_matchers: [["project", "=", "o11y"]]
      receiver: rootly-o11y
    - object_matchers: [["grafana_folder", "=", "yucca"]]
      receiver: rootly-yucca
    - object_matchers: [["grafana_folder", "=", "o11y"]]
      receiver: rootly-o11y
```

Rules owned by one project set `project: <project>` as a rule label, which both routes them and pins the label even when the query aggregates it away. A shared rule that should reach each remote cluster's own team must instead keep `project` in its aggregation and set **no** `project` rule label, since a rule label overrides the series label and would send every cluster's firing to one team. `o11y-external-secret-not-ready` in `alerts-fleet.yaml` works this way (`by (project, env, cluster, ...)`); a firing for a project with no route of its own falls through to the `o11y` folder route. The other fleet rule, `o11y-cluster-silent`, is o11y's own: it aggregates `by (cluster)` alone and sets `project: o11y`, so a cluster that stops reporting pages o11y, not the cluster's owner. A project that wants its own page for that ships a guarded absence rule in its folder (bootstrap's `ClusterMetricsGone`, for example). Notifications group by `project`, `grafana_folder`, `alertname` and `cluster`, so the same rule firing in two clusters arrives as two grouped notifications rather than one blended message.

**Datasources and tenants.** Two Prometheus-type datasources front the same store. `VictoriaMetrics` (uid `VictoriaMetrics`, the default) carries this cluster's own tenant in its URL and goes through the `self-select` vmauth, which routes only that path, so anything that does not pick a datasource explicitly sees only o11y's series. `VictoriaMetrics Fleet` (uid `VictoriaMetricsFleet`) reads the multitenant endpoint across every tenant, including tenant 0 where unmigrated remotes still land; it is the explicit opt-in for cross-cluster dashboards and rules (`alerts-fleet.yaml`). Tenancy is carried by the datasource URL, never by dashboard JSON or rule queries: both keep filtering and grouping on the `cluster` label, which survives the tenant split unchanged.

The default datasource is therefore right only for o11y's own rules and boards. Every other project's series live in its own tenant (or tenant 0), which only `VictoriaMetrics Fleet` can see, so a remote project (every bundle, and another project's CRs authored here) uses Fleet throughout: `datasourceUid: VictoriaMetricsFleet` on every alert query node, since a rule cannot use a `$datasource` variable, and on dashboards a `$datasource` variable with the regex `/^VictoriaMetrics Fleet$/`. A remote rule left on the default datasource evaluates to NoData, which the usual `noDataState: OK` keeps Normal through a real outage; yucca's `o11y/README.md` records one that went unalerted this way. Fleet serves every tenant, so a remote project also scopes each selector with `project="<project>"`, or a generic one (Flux, cert-manager, Kubernetes) fires on other projects' clusters.

**Alert rule anatomy.** A `GrafanaAlertRuleGroup` (`folderRef: <project>`, an `interval`) with `rules[]`; each rule is a query stage on a Prometheus datasource (uid `VictoriaMetrics` for o11y's own rules, `VictoriaMetricsFleet` for the fleet rules and every remote project's, see Datasources and tenants) feeding a `__expr__` threshold stage, plus `labels` (at least `severity`) and `annotations`: a one-line `summary` and a `description` of what to check, which Rootly and Zulip show for every firing alert, and optionally a `runbook_url`. See `base/grafana/app/alerts-o11y.yaml` for the pattern (a heartbeat plus target-down and ingestion-stalled rules). Rules that span clusters aggregate `by (cluster)` so each cluster raises its own instance and carries its `cluster` label into notification grouping; store-local rules (the heartbeat, ingestion-stalled) don't.

## If you ship metrics to this cluster and want dashboards/alerts

1. Pick a delivery model: **Model A** (recommended for a separate repo/cluster - you own a signed bundle, o11y adds one OCIRepository) or **Model B** (PR the CRs into `base/grafana`).
2. Everything you ship files under **your project's folder**; ask for one if it does not exist.
3. Set `project: <project>` as a rule label on your rules (folder routing is the fallback). Ask for your project to be added to the Rootly module's `projects` list; once an operator applies `deployment/modules/rootly/cluster` in both environments, that gives you a Rootly alert source, a service, Zulip delivery to `yucca-alerts` under a `<project>-<env>` topic, and the `ROOTLY_ALERTS_<PROJECT>_URL` vault item. The `rootly-<project>` contact point, its ExternalSecret and the two routes in `base/grafana/app` are a second change here, merged after that apply because the ExternalSecret needs the item (bootstrap: #388, then #389).
4. Query `VictoriaMetrics Fleet`, never the default `VictoriaMetrics` datasource, which sees only o11y's own tenant: alerts set `datasourceUid: VictoriaMetricsFleet` on every query node, dashboards use a `$datasource` variable with the regex `/^VictoriaMetrics Fleet$/`, and every selector carries `project="<project>"` (see Datasources and tenants).
5. Tag dashboards by signal/layer in the JSON (`metrics`, `logs`, `infra`, ...) so they stay filterable across folders (see Tags). Alerts that compare across clusters aggregate `by (cluster)`; stamp the five identity labels on your series (see the [shipping guide](05-shipping-metrics-guide.md#labels)) so per-cluster alerting works.

## How updates flow

- **Model A:** edit in the source repo, merge to `main` -> CI pushes the `:main` artifact (signed) -> o11y's OCIRepository picks it up within its `interval` -> Kustomization applies -> grafana-operator syncs. Roughly a minute end to end.
- **Model B:** PR the CR change here -> merge -> Flux reconciles `base/grafana`.
