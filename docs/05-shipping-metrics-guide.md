# Shipping metrics to the central store

This cluster is the central VictoriaMetrics store for all FUTO clusters. A remote cluster does not push into a special API: it runs its own `vmagent` and **remote-writes** the standard Prometheus format to an ingestion gateway here. This guide covers the two network paths in, the config each needs, and how to verify data is landing.

Both paths terminate at a `vmauth` gateway that proxies to the same `vminsert` tier, so the ingestion API, the label rules, and the resulting data are identical no matter which you pick. The only differences are the hostname, the transport, and whether a token is required.

## The two paths

| | Over the NetBird mesh | Over the internet |
|---|---|---|
| Gateway hostname | `vmauth.<mesh-domain>` | `vmauth.<app-domain>` |
| Envoy gateway | `mesh` (mesh-only VIP) | `envoy` (public, via OVH IPLB) |
| Auth | none; the NetBird ACL is the gate | shared bearer token |
| Transport | private overlay, never leaves the mesh | public internet, TLS at Envoy |
| Use when | the remote cluster is already a mesh peer | the remote cluster is not on the mesh |

Prefer the mesh path for clusters already joined to the FUTO NetBird mesh: there is no token to distribute or rotate, and the traffic never traverses the public internet. Use the internet path for anything not on the mesh. Both may be used at once; they write to the same store.

### Per-environment endpoints

| | staging | production |
|---|---|---|
| Mesh gateway | `vmauth.staging.o11y.futo.network` | `vmauth.o11y.futo.network` |
| Public gateway | `vmauth.staging.futostatus.com` | `vmauth.futostatus.com` |

Both gateway URLs are also published to the per-environment shared 1Password vault (`shared_tf_staging` / `shared_tf_prod`), alongside the bearer token, so a consuming cluster can pull its endpoint from the vault instead of hardcoding the hostname:

| Item | Value (field `password`) |
|---|---|
| `O11Y_VICTORIAMETRICS_VMAUTH_MESH_URL` | `https://vmauth.<mesh-domain>` |
| `O11Y_VICTORIAMETRICS_VMAUTH_PUBLIC_URL` | `https://vmauth.<app-domain>` |

The items hold the bare origin (scheme and host, no path); append the insert or select path for your shipper. They are Terraform-managed by `deployment/modules/victoria-metrics/cluster`; the token item is managed by hand.

The metrics remote-write path is the same on every host:

```text
/insert/0/prometheus/api/v1/write
```

(The `0` in the path is nominal: the central `vmauth` rewrites it onto the multitenant insert endpoint and the store assigns the real tenant from the `project` and `cluster` labels, see Tenants below.)

## Prerequisites (both paths)

* **A `vmagent` with a persistent disk buffer.** The central store is a single point of failure for observability; a per-remote disk buffer means a central outage replays on recovery instead of dropping data. Give `vmagent` a PVC and point `-remoteWrite.tmpDataPath` at it (or, for Prometheus, rely on its WAL and tune `queue_config`).
* **The mandatory identity labels.** See [Labels](#labels).

## Option A: over the NetBird mesh

The remote cluster must be a NetBird peer whose group is permitted by ACL to reach this cluster's mesh gateway, and its `vmagent` must egress through a mesh interface and resolve `vmauth.<mesh-domain>` via mesh DNS. See the NetBird section of the [infrastructure guide](02-infrastructure-architecture-guide.md) for how peers and ACLs are modelled; on this side, `external-secrets` reaching the bootstrap 1Password Connect is the reference pattern (a Multus egress interface plus mesh DNS).

No token is needed: the mesh ACL is the only gate. The gateway still terminates TLS with a publicly-trusted `*.<mesh-domain>` certificate, so `https://` works with no custom CA.

```yaml
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMAgent
metadata:
  name: central-forwarder
spec:
  externalLabels:
    project: yucca
    env: prod
    cluster: father       # unique per remote, mandatory
    provider: hetzner
    region: fsn
  remoteWrite:
    - url: https://vmauth.o11y.futo.network/insert/0/prometheus/api/v1/write
  extraArgs:
    remoteWrite.tmpDataPath: /vmagent-buffer
  # ...plus a PVC mounted at /vmagent-buffer for the disk buffer
```

## Option B: over the internet

The public gateway rejects anonymous requests, so a **shared bearer token** is required. It lives in 1Password as item `O11Y_VICTORIAMETRICS_VMAUTH_PASSWORD` (field `password`), in the same vault as the gateway URL items above. Clusters that share the vault can pull it with an ExternalSecret; otherwise create the Secret by hand. Rotating the token for everyone is a single edit to that vault item.

```yaml
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMAgent
metadata:
  name: central-forwarder
spec:
  externalLabels:
    project: yucca
    env: prod
    cluster: father       # unique per remote, mandatory
    provider: hetzner
    region: fsn
  remoteWrite:
    - url: https://vmauth.futostatus.com/insert/0/prometheus/api/v1/write
      bearerTokenSecret:
        name: o11y-remote-write-token   # a Secret holding the vault token
        key: token
  extraArgs:
    remoteWrite.tmpDataPath: /vmagent-buffer
  # ...plus a PVC mounted at /vmagent-buffer for the disk buffer
```

If the remote runs Prometheus rather than `vmagent`, the equivalent is:

```yaml
global:
  external_labels:
    project: yucca
    env: prod
    cluster: father
    provider: hetzner
    region: fsn
remote_write:
  - url: https://vmauth.futostatus.com/insert/0/prometheus/api/v1/write
    authorization:
      type: Bearer
      credentials_file: /etc/o11y/token
```

## Labels

Everything lands in one tenant, distinguished by labels rather than VictoriaMetrics multitenancy: one organization, mutual trust, everything queryable together. Every shipper - metrics and logs alike - must stamp the same five identity labels on everything it sends:

* **`project`** - which project the cluster belongs to (`o11y`, `yucca`, ...).
* **`env`** - short environment name: `dev`, `staging`, or `prod` (not `production`).
* **`cluster`** (mandatory, unique) - a short name unique to the cluster (`father`, `o11y`, ...), so series never collide with another cluster's, and so alerting can tell clusters apart: o11y's alert rules aggregate `by (cluster)` and notifications group on it, so a missing or reused `cluster` label collapses every cluster into a single alert and a single notification. Cheap to enforce now, painful to retrofit.
* **`provider`** - infrastructure provider (`ovh`, `hetzner`, ...).
* **`region`** - the IATA/ICAO airport code nearest the site (`fsn`, `aus`, ...). A cluster spanning several sites uses `global` (the o11y clusters do: their nodes span three OVH datacenters).

The value sets are open - these are the conventions, not a closed enumeration; the authority for any given cluster is its own shipper config. The o11y clusters stamp `project=o11y, env=<staging|prod>, cluster=o11y, provider=ovh, region=global`, with `cluster` and `env` supplied per environment from `CLUSTER_NAME`/`CLUSTER_ENV` in `kubernetes/clusters/<env>/cluster-settings.yaml`.

`externalLabels` only tags *scraped* series; if the shipper also forwards pushed data (e.g. OTLP app metrics through a `vmagent`), apply the same labels with a relabel config instead so ingested series are tagged too.

### Make the identity labels win

External labels are only added to series that lack the label. Some exporters emit their own `cluster` (CloudNativePG names its Cluster CR that way, the Ceph exporter names the Ceph cluster), and those series then reach the store carrying the exporter's value instead of yours: they fall out of your dashboards and alerts, and land in tenant 0 because the registry does not know that cluster. The store cannot repair this, since the real value is gone by the time it arrives. Apply the identity labels so they take precedence and keep the exporter's value under another name. In `vmagent`, one remote-write relabel rule pair does it for scraped and pushed data alike:

```yaml
spec:
  inlineRelabelConfig:
    - source_labels: [cluster]
      regex: (.+)
      target_label: exported_cluster
    - target_label: cluster
      replacement: father
```

Prometheus users get the same effect by setting `cluster` as a target label in `relabel_configs` for every scrape job: with the default `honor_labels: false` a conflicting scraped label is renamed to `exported_cluster` automatically.

### Shippers that push instead of scrape

The fleet-wide `o11y cluster stopped reporting` alert keys on `up`, which only scrapers emit. A pusher such as a serverless worker never produces `up` and often ships in bursts, so it can go dark without anyone noticing. Such a shipper should emit one steady heartbeat metric and own an `absent_over_time` alert on it in its project folder, with a window matched to its push cadence.

## Tenants

Metrics are also keyed by VictoriaMetrics tenant (`accountID:projectID`): `accountID` is the project, `projectID` is the cluster within it. Shippers never see tenant IDs. They write to the `/insert/0/...` URL with the shared token as shown above, the central `vmauth` rewrites that onto the multitenant insert endpoint, and `vminsert` assigns the tenant from the `project` and `cluster` labels using the relabel rules in `kubernetes/apps/base/victoria-metrics/app/configmap-vminsert-relabel.yaml`, which is the tenant registry. A cluster with no rule lands in tenant 0.

IDs are unique within a store, and an environment pair (a prod cluster and its staging twin, each shipping to its own store) shares the same tenant so tenant-scoped config carries across environments unchanged; clusters with no twin take the next free number in their project. `accountID` 0 and `projectID` 0 are never assigned: any cluster without a rule pair lands in `0:0`, whatever its project. Rules are keyed on `project;cluster` for both labels, never on the project alone, so each cluster migrates independently and a new cluster in a known project cannot be moved by accident. This table records the assignments; a cluster is live on its tenant exactly when its rule pair is in the ConfigMap, so add the row and the rule in the same change.

| Project | accountID | Cluster | Env | Store | Tenant |
|---|---|---|---|---|---|
| o11y | 1 | o11y | staging, prod | both | `1:1` |
| yucca | 2 | father | prod | production | `2:1` |
| yucca | 2 | netops | prod | production | `2:2` |
| yucca | 2 | spice | prod | production | `2:3` |
| yucca | 2 | luke | staging | staging | `2:4` |
| harbor | 3 | harbor-infra-prod | prod | production | `3:1` |
| harbor | 3 | harbor-infra-staging | staging | staging | `3:1` |
| fip | 4 | azad | prod | production | `4:1` |
| fmeet | 5 | serverless | staging, prod | both | `5:1` |

Onboarding a cluster onto its own tenant is a central-side change only: add its rule pair, for example

```yaml
- source_labels: [project, cluster]
  regex: yucca;father
  target_label: vm_account_id
  replacement: "2"
- source_labels: [project, cluster]
  regex: yucca;father
  target_label: vm_project_id
  replacement: "1"
```

`vminsert` reloads the file without a restart. No backfill is needed: the cluster's older history stays in tenant 0, where the Fleet datasource still reads it alongside the new tenant, and ages out with retention. The o11y rules also match samples with `project=o11y` and no `cluster` label, which is what its own `vmalert` writes. The o11y cluster's own IDs come from `CLUSTER_VMETRICS_ACCOUNT_ID` and `CLUSTER_VMETRICS_PROJECT_ID` in `kubernetes/clusters/<env>/cluster-settings.yaml`, which also drive its tenant-scoped reads (the default Grafana datasource, `vmalert` and the MCP server).

Fleet-wide reads use the `/select/multitenant/prometheus` endpoint, which spans every tenant including tenant 0, so cross-cluster dashboards and alerts keep working while clusters migrate. Logs stay in a single tenant and are distinguished by labels only.

## Verify data is arriving

From the central side, query for the remote's series. Over the mesh (no token), the browsable UI is at `https://vmetrics.<mesh-domain>/select/multitenant/vmui/`, or query the API directly:

```bash
curl -s 'https://vmauth.o11y.futo.network/select/0/prometheus/api/v1/query' \
  --data-urlencode 'query=count(up{cluster="father"})'
```

Over the internet, the same query with the token:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://vmauth.futostatus.com/select/0/prometheus/api/v1/query' \
  --data-urlencode 'query=count(up{cluster="father"})'
```

A non-zero count means the remote's series are landing. If it is zero, check the remote `vmagent`'s own `vmagent_remotewrite_*` metrics for send errors, and confirm the `cluster` label is set.

## Logs, on the same gateways

Logs ride the identical `vmauth` hostnames (VictoriaLogs sits behind the same gateways). Point a log shipper at `https://vmauth.<host>/insert/<format>/...`, where `<format>` is one of `native`, `jsonline`, `opentelemetry`, `loki`, or `elasticsearch`; read back with `/select/logsql/...`. Auth is the same as for metrics: none on the mesh, bearer token on the internet.

Logs carry the same identity labels as metrics, stamped as fields by the shipper - e.g. the `victoria-logs-collector` chart takes them via `extraFields`.

## What backs this centrally

For maintainers, the ingestion config lives in `kubernetes/apps/base/victoria-metrics-users/app/`:

* `vmuser-remote-clusters.yaml` - the `VMUser` behind the public gateway. It holds the shared token (via ExternalSecret) and the allowed path set: metrics and logs insert **and** select (remote clusters can read back, not only write).
* `vmauth-mesh-unauth.yaml` - the unauthenticated `mesh-unauth` `VMAuth` on the mesh gateway, with the same path set exposed through `unauthorizedUserAccessSpec`.

The public gateway itself is the `vmauth` defined in the VictoriaMetrics release (`kubernetes/apps/base/victoria-metrics/app/helmrelease.yaml`), reached at `vmauth.<CLUSTER_APP_DOMAIN>`.
