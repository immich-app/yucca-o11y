# Application architecture guide

The workloads running on the cluster — the ingress edge, the observability stack, and their supporting operators. Everything is Flux-managed and lives in the `o11y` namespace unless noted.

## Ingress edge

### Envoy Gateway

Envoy Gateway is the only external ingress. It runs one replica per worker with a hostname topology-spread constraint, so every IPLB backend has a local endpoint under `externalTrafficPolicy: Local`. The OVH load balancer does TCP passthrough to Envoy's NodePort; TLS terminates at Envoy. A client traffic policy parses PROXY protocol v2 (which the IPLB prepends) as optional, so the LB's bare-TCP health probe isn't reset while real client connections still surface the true source IP. Platform services attach to the gateway through HTTPRoutes (Grafana, vmauth, the echo test app).

### Mesh gateway

A second Envoy Gateway (`mesh`, in `envoy-system`) serves NetBird peers instead of the public internet; it hangs off a pinned VIP Service the mesh advertises (see the infrastructure guide's NetBird section). It terminates TLS with a `*.<mesh-domain>` wildcard from the same cert-manager pipeline for mesh-facing HTTPRoutes — an unauthenticated vmauth at `vmauth.<mesh-domain>` gives other FUTO clusters a remote-write path that never leaves the mesh — and carries a TLS-**passthrough** listener on `:6443` fronting the kube-apiserver as `kube.<mesh-domain>`: SNI-routed to the `kubernetes` Service, apiserver's own certificate end-to-end, load-balanced across all three control planes.

### TLS certificates

cert-manager issues short-lived ECDSA P-256 wildcard certificates with always-rotate, using Let's Encrypt with the OVH DNS-01 challenge webhook. The certificate `dnsNames` are defined once in the base manifests using the `CLUSTER_APP_DOMAIN` placeholder and resolve per environment from `cluster-settings` — staging gets `*.staging.futostatus.com`, production the bare-domain wildcards.

## VictoriaMetrics — the central metrics store

This cluster's VictoriaMetrics is the **central metrics store for all FUTO clusters**. Other Kubernetes clusters each run their own `vmagent` and remote-write into this cluster; it is the ingestion target plus the query and alerting brain for everyone.

* **Storage** — VMCluster mode with `replicationFactor=2`, `vmstorage` spread one-per-worker across the three DCs on `openebs-spare-disk`; retention is set per environment via `CLUSTER_VMETRICS_RETENTION` (30d staging, 120d production). The `vmstorage`, `vminsert`, and `vmselect` tiers scale independently.
* **Local collection**: a `vmagent` (with a persistent disk buffer) scrapes this cluster and remote-writes to the local `vminsert`'s multitenant endpoint. It tags series with the cluster's identity, from which `vminsert` derives the tenant.
* **Alerting** — `vmalert` evaluates rules; notifications are blackholed for now (no Alertmanager yet), so rules still evaluate and recording rules still write.
* **Ingestion gateway** — a locked-down `vmauth` (no anonymous access, run as an HA pair) fronts `vminsert` and is exposed publicly at `vmauth.<CLUSTER_APP_DOMAIN>` through the Envoy Gateway and IPLB with cert-manager TLS.

### Tenancy and auth

Each cluster lands in its **own VictoriaMetrics tenant** (`accountID` = project, `projectID` = cluster; the registry lives in the [shipping guide](05-shipping-metrics-guide.md#tenants)), and every series also carries the mandatory identity labels: one organization, mutual trust, everything queryable together through the multitenant read endpoint. Tenancy is derived centrally rather than declared by shippers: a **single shared bearer token** authenticates all remote clusters, the `VMUser` it is bound to rewrites writes onto the multitenant insert endpoint, and `vminsert` relabeling maps each sample's `project`/`cluster` labels to a tenant. Remotes ship only the five identity labels. Per-tenant enforcement is available later by splitting a remote onto its own token pinned to its tenant path. The token is stored in 1Password and injected via ExternalSecret into that `VMUser`. Because the operator installs the `VMUser` CRD, those resources live in a separate Flux Kustomization that depends on the VictoriaMetrics release and external-secrets, so they don't race CRD registration.

### Label convention

Every shipper — metrics and logs, remote and local — stamps the same five identity labels: `project`, `env`, `cluster`, `provider`, `region`. `cluster` uniqueness is mandatory so series don't collide across clusters — cheap to enforce now, painful to retrofit. The [shipping guide](05-shipping-metrics-guide.md#labels) defines the values; this cluster's own pair comes from `CLUSTER_NAME`/`CLUSTER_ENV` in `cluster-settings`.

### Onboarding a remote cluster

On the central side, add the cluster to the tenant registry (until then it lands in tenant 0). On the remote cluster: pull the shared token from the same vault item into a Secret, then configure its `vmagent` with a persistent disk buffer (so a central outage doesn't lose data; it replays on recovery), the mandatory external labels, and a remote-write to the public `vmauth` endpoint authenticated with the bearer token. To rotate access for everyone, change the vault item; ExternalSecrets re-sync on both sides. Per-cluster revocation, if ever needed, means splitting into per-cluster vault items and `VMUser`s.

### Operating notes

The central store is a single point of failure for all observability, mitigated by the per-remote disk buffers, the RF=2 / three-DC resilience, and meta-monitoring that must live **outside** this cluster (it can't watch itself). Total load scales with the sum of each cluster's active series, so grow the storage and insert/select tiers as clusters onboard and add cardinality guardrails so one misbehaving remote can't overwhelm the store.

## VictoriaLogs

Logs run as a **VLDistributed** resource, declared in the `vldistributed` block of the same `victoria-metrics-k8s-stack` HelmRelease that runs the metrics tier and reconciled by the VictoriaMetrics operator. VictoriaLogs has no cross-node replication (`vlinsert` shards across `vlstorage` and there is no `replicationFactor`), so durability comes from two independent zones rather than from replication inside one cluster.

Each zone is a `VLCluster` with a single `vlstorage` at `CLUSTER_VMLOGS_SIZE` on `CLUSTER_VMLOGS_STORAGE_CLASS`, retention per environment via `CLUSTER_VMLOGS_RETENTION` (30d staging, 120d production). The VictoriaLogs release is not pinned here: like the metrics components it follows the chart's `global.versions`, so a k8s-stack bump upgrades the zones (one at a time, see below). A hostname topology spread with `DoNotSchedule` on `app.kubernetes.io/name: vlstorage`, the same idiom the metrics tier uses, keeps the two zones' storage on different workers, which is what makes them independently survivable: both environments have only three workers and the PVCs are node-local, so two zones sharing a node would fail together.

The operator runs one `vlagent` per zone, each replicating every log line to every zone's `vlinsert`. Those agents are given an explicit 20Gi persistent queue: left unconfigured the operator falls back to an `emptyDir`, which would lose whatever is buffered for a down zone on any agent restart, defeating the point of the agent. The operator divides the PVC across destinations, so two zones means 10Gi of buffer each. The agents carry the same hostname spread as the storage, because their queue PVCs are node-local too and the managed VMAuth routes every insert only to them: two agents pinned to one worker would take the whole write path down with that worker. It fronts the whole thing with a managed `VMAuth` named `victoria-logs` on port 8427, run at two replicas with a disruption budget and hostname spread like the public metrics gateway, since every log read and write funnels through it. That one endpoint serves both directions: `/insert/*` is load-balanced across the zone agents, `/select/*` is `first_available` across the zone selects, so a degraded zone fails over. Everything points at it: the `victoria-logs-collector` DaemonSet, the external clusters arriving through the two vmauth gateways, the Grafana datasource, `victoria-logs-mcp`, and the `vlogs.` mesh route.

The CR is named `victoria-logs` explicitly (the chart's `vldistributed.name`) rather than inheriting the release's `fullnameOverride`. The operator names the managed VMAuth after the CR, so a CR called `victoria-metrics` would adopt and overwrite the public metrics gateway of that name; naming the CR removes that collision and makes every derived object (`victoria-logs-a`, `vlstorage-victoria-logs-a`) say what it is. The `victoria-metrics` Flux Kustomization health-checks the CR through `healthCheckExprs` on `status.updateStatus`, so consumers that depend on it wait for the zones to be operational, not merely for the CR to be accepted.

Upgrades are orchestrated by the operator, one zone at a time: it drains the zone's agent queue, removes the zone from the VMAuth read and write targets, reconciles it, waits for readiness, restores it, then pauses before the next zone. `search.allowPartialResponse` is deliberately left unset, because a partial response is a 200 with silently incomplete data and vmauth fails over only on an error status.

The previous sharded cluster (`victoria-logs-cluster` chart, three `vlstorage` shards, `kubernetes/apps/base/victoria-logs/`) is kept for a transition period as a **read-only legacy tier**: its `vlinsert` is disabled so nothing can write to it, and it is reachable only through the `VictoriaLogs Legacy` Grafana datasource (uid `VictoriaLogsLegacy`). Nothing was migrated; the old history simply stays queryable there while it ages out under the old retention, after which the tier, the datasource and the orphaned PVCs are removed. The default `VictoriaLogs` datasource, `victoria-logs-mcp`, the `vlogs.` mesh route and both gateways only ever see the new tier. The decommission checklist lives in the [cutover runbook](runbooks/victoria-logs-ha-cutover/README.md#decommission-the-legacy-tier).

Logs stay single-tenant (tenant 0) and are identified by the five labels (`project`/`env`/`cluster`/`provider`/`region`) carried as fields. VictoriaLogs does have tenants, an `(AccountID, ProjectID)` pair like VictoriaMetrics, but set via request headers rather than URL path segments, and there is no cross-tenant read: only `/insert/multitenant/native` exists, with no select equivalent. Splitting logs across tenants would therefore cost fleet-wide queries entirely. Tracked upstream as [VictoriaLogs#91](https://github.com/VictoriaMetrics/VictoriaLogs/issues/91); revisit if it ships.

## Grafana

Grafana runs as a 3-replica HA deployment managed by the Grafana operator, with non-blocking rolling updates (zero surge, one unavailable) and one replica per worker via a topology-spread constraint. Pod storage is ephemeral — **all state lives in Postgres** — and the replicas share a single security secret key (from 1Password) so signed cookies and sessions validate on any replica. Grafana connects to its Postgres over TLS; the password is supplied as an environment variable rather than written into config. It is reached at `grafana.<CLUSTER_APP_DOMAIN>` and the alternate domain.

## CloudNativePG

Grafana's database is a CloudNativePG cluster. The operator runs in the `cnpg-system` namespace; the `grafana-postgres` cluster runs three instances with required pod anti-affinity (one per worker) on `openebs-spare-disk`. Its credentials are basic-auth Secrets (a superuser and the Grafana owner) sourced from 1Password — CloudNativePG requires that secret type, and the database owner's username must match the secret.

## Supporting components

* **external-secrets** — syncs 1Password items into Kubernetes Secrets through cluster secret stores backed by the **bootstrap cluster's** 1Password Connect (`opc.o11y.futo.network`), reached over the NetBird mesh: the controller pod carries a Multus egress interface and resolves the endpoint via mesh DNS. Nearly every app above gets its credentials this way; the auth token is Terraform-seeded.
* **Multus** — meta-CNI providing opt-in secondary pod interfaces; today only the `netbird-egress` attachment used by external-secrets.
* **grafana-operator** — manages the Grafana instance plus dashboard and datasource resources, which VictoriaMetrics' chart provisions.
* **prometheus-operator CRDs** — the ServiceMonitor/PrometheusRule CRDs the VM stack consumes.
* **OpenEBS** — the local-hostpath provisioner backing the `openebs-system-disk` and `openebs-spare-disk` StorageClasses.
* **Spegel** — peer-to-peer image registry mirror across nodes.
* **descheduler**, **reloader**, **metrics-server** — pod rebalancing, config-change pod reloads, and the resource-metrics API.
