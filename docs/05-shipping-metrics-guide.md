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

The metrics remote-write path is the same on every host:

```text
/insert/0/prometheus/api/v1/write
```

(`0` is the VictoriaMetrics tenant; everything lands in a single tenant, see Labels below.)

## Prerequisites (both paths)

* **A `vmagent` with a persistent disk buffer.** The central store is a single point of failure for observability; a per-remote disk buffer means a central outage replays on recovery instead of dropping data. Give `vmagent` a PVC and point `-remoteWrite.tmpDataPath` at it (or, for Prometheus, rely on its WAL and tune `queue_config`).
* **The mandatory `cluster` external label** (plus `env` and `region`). See Labels.

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
    cluster: my-cluster   # unique per remote, mandatory
    env: prod
    region: eu-west
  remoteWrite:
    - url: https://vmauth.o11y.futo.network/insert/0/prometheus/api/v1/write
  extraArgs:
    remoteWrite.tmpDataPath: /vmagent-buffer
  # ...plus a PVC mounted at /vmagent-buffer for the disk buffer
```

## Option B: over the internet

The public gateway rejects anonymous requests, so a **shared bearer token** is required. It lives in 1Password as item `O11Y_VICTORIAMETRICS_VMAUTH_PASSWORD` (field `password`). Clusters that share the vault can pull it with an ExternalSecret; otherwise create the Secret by hand. Rotating the token for everyone is a single edit to that vault item.

```yaml
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMAgent
metadata:
  name: central-forwarder
spec:
  externalLabels:
    cluster: my-cluster   # unique per remote, mandatory
    env: prod
    region: eu-west
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
    cluster: my-cluster
    env: prod
    region: eu-west
remote_write:
  - url: https://vmauth.futostatus.com/insert/0/prometheus/api/v1/write
    authorization:
      type: Bearer
      credentials_file: /etc/o11y/token
```

## Labels

Everything lands in one tenant, distinguished by labels rather than VictoriaMetrics multitenancy: one organization, mutual trust, everything queryable together. Every remote `vmagent` must set:

* **`cluster`** (mandatory) - a name unique to the remote cluster, so series never collide with another cluster's, and so alerting can tell clusters apart: o11y's alert rules aggregate `by (cluster)` and notifications group on it, so a missing or reused `cluster` label collapses every cluster into a single alert and a single notification. Cheap to enforce now, painful to retrofit.
* **`env`** and **`region`** - conventional, so dashboards and alerts can slice by environment and location.

## Verify data is arriving

From the central side, query for the remote's series. Over the mesh (no token), the browsable UI is at `https://vmetrics.<mesh-domain>/select/0/vmui/`, or query the API directly:

```bash
curl -s 'https://vmauth.o11y.futo.network/select/0/prometheus/api/v1/query' \
  --data-urlencode 'query=count(up{cluster="my-cluster"})'
```

Over the internet, the same query with the token:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://vmauth.futostatus.com/select/0/prometheus/api/v1/query' \
  --data-urlencode 'query=count(up{cluster="my-cluster"})'
```

A non-zero count means the remote's series are landing. If it is zero, check the remote `vmagent`'s own `vmagent_remotewrite_*` metrics for send errors, and confirm the `cluster` label is set.

## Logs, on the same gateways

Logs ride the identical `vmauth` hostnames (VictoriaLogs sits behind the same gateways). Point a log shipper at `https://vmauth.<host>/insert/<format>/...`, where `<format>` is one of `native`, `jsonline`, `opentelemetry`, `loki`, or `elasticsearch`; read back with `/select/logsql/...`. Auth is the same as for metrics: none on the mesh, bearer token on the internet.

## What backs this centrally

For maintainers, the ingestion config lives in `kubernetes/apps/base/victoria-metrics-users/`:

* `vmuser-remote-clusters.yaml` - the `VMUser` behind the public gateway. It holds the shared token (via ExternalSecret) and the allowed path set: metrics and logs insert **and** select (remote clusters can read back, not only write).
* `vmauth-mesh-unauth.yaml` - the unauthenticated `mesh-unauth` `VMAuth` on the mesh gateway, with the same path set exposed through `unauthorizedUserAccessSpec`.

The public gateway itself is the `vmauth` defined in the VictoriaMetrics release (`kubernetes/apps/base/victoria-metrics/helmrelease.yaml`), reached at `vmauth.<CLUSTER_APP_DOMAIN>`.
