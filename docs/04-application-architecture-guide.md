# Application architecture guide

The workloads running on the cluster — the ingress edge, the observability stack, and their supporting operators. Everything is Flux-managed and lives in the `o11y` namespace unless noted.

## Ingress edge

### Envoy Gateway

Envoy Gateway is the only external ingress. It runs one replica per worker with a hostname topology-spread constraint, so every IPLB backend has a local endpoint under `externalTrafficPolicy: Local`. The OVH load balancer does TCP passthrough to Envoy's NodePort; TLS terminates at Envoy. A client traffic policy parses PROXY protocol v2 (which the IPLB prepends) as optional, so the LB's bare-TCP health probe isn't reset while real client connections still surface the true source IP. Platform services attach to the gateway through HTTPRoutes (Grafana, vmauth, the echo test app).

### TLS certificates

cert-manager issues short-lived ECDSA P-256 wildcard certificates with always-rotate, using Let's Encrypt with the OVH DNS-01 challenge webhook. The certificate `dnsNames` are defined once in the base manifests using the `APP_DOMAIN` placeholders and resolve per environment from `cluster-settings` — staging gets `*.staging.futostatus.com`, production the bare-domain wildcards.

## VictoriaMetrics — the central metrics store

This cluster's VictoriaMetrics is the **central metrics store for all FUTO clusters**. Other Kubernetes clusters each run their own `vmagent` and remote-write into this cluster; it is the ingestion target plus the query and alerting brain for everyone.

* **Storage** — VMCluster mode with `replicationFactor=2`, `vmstorage` spread one-per-worker across the three DCs on `openebs-spare-disk` with 90-day retention. The `vmstorage`, `vminsert`, and `vmselect` tiers scale independently.
* **Local collection** — a `vmagent` (with a persistent disk buffer) scrapes this cluster and remote-writes to the local `vminsert`. It tags series with the cluster's identity.
* **Alerting** — `vmalert` evaluates rules; notifications are blackholed for now (no Alertmanager yet), so rules still evaluate and recording rules still write.
* **Ingestion gateway** — a locked-down `vmauth` (no anonymous access, run as an HA pair) fronts `vminsert` and is exposed publicly at `vmauth.<APP_DOMAIN>` through the Envoy Gateway and IPLB with cert-manager TLS.

### Tenancy and auth

Everything lands in a **single tenant**, distinguished by a mandatory `cluster` external label rather than VictoriaMetrics multitenancy — one organization, mutual trust, everything queryable together. A **single shared bearer token** authenticates all remote clusters; it is stored in 1Password and injected via ExternalSecret into a `VMUser` that grants write-only access. Because the operator installs the `VMUser` CRD, those resources live in a separate Flux Kustomization that depends on the VictoriaMetrics release and external-secrets, so they don't race CRD registration.

### Label convention

Every remote `vmagent` must set a unique `cluster` label (plus `env` and `region`) so series don't collide across clusters. `cluster` is mandatory — cheap to enforce now, painful to retrofit.

### Onboarding a remote cluster

Nothing changes on the central side. On the remote cluster: pull the shared token from the same vault item into a Secret, then configure its `vmagent` with a persistent disk buffer (so a central outage doesn't lose data — it replays on recovery), the mandatory external labels, and a remote-write to the public `vmauth` endpoint authenticated with the bearer token. To rotate access for everyone, change the vault item; ExternalSecrets re-sync on both sides. Per-cluster revocation, if ever needed, means splitting into per-cluster vault items and `VMUser`s.

### Operating notes

The central store is a single point of failure for all observability, mitigated by the per-remote disk buffers, the RF=2 / three-DC resilience, and meta-monitoring that must live **outside** this cluster (it can't watch itself). Total load scales with the sum of each cluster's active series, so grow the storage and insert/select tiers as clusters onboard and add cardinality guardrails so one misbehaving remote can't overwhelm the store.

## Grafana

Grafana runs as a 3-replica HA deployment managed by the Grafana operator, with non-blocking rolling updates (zero surge, one unavailable) and one replica per worker via a topology-spread constraint. Pod storage is ephemeral — **all state lives in Postgres** — and the replicas share a single security secret key (from 1Password) so signed cookies and sessions validate on any replica. Grafana connects to its Postgres over TLS; the password is supplied as an environment variable rather than written into config. It is reached at `grafana.<APP_DOMAIN>` and the alternate domain.

## CloudNativePG

Grafana's database is a CloudNativePG cluster. The operator runs in the `cnpg-system` namespace; the `grafana-postgres` cluster runs three instances with required pod anti-affinity (one per worker) on `openebs-spare-disk`. Its credentials are basic-auth Secrets (a superuser and the Grafana owner) sourced from 1Password — CloudNativePG requires that secret type, and the database owner's username must match the secret.

## Supporting components

* **external-secrets + 1Password Connect** — sync 1Password items into Kubernetes Secrets through a cluster secret store; nearly every app above gets its credentials this way.
* **grafana-operator** — manages the Grafana instance plus dashboard and datasource resources, which VictoriaMetrics' chart provisions.
* **prometheus-operator CRDs** — the ServiceMonitor/PrometheusRule CRDs the VM stack consumes.
* **OpenEBS** — the local-hostpath provisioner backing the `openebs-system-disk` and `openebs-spare-disk` StorageClasses.
* **Spegel** — peer-to-peer image registry mirror across nodes.
* **descheduler**, **reloader**, **metrics-server** — pod rebalancing, config-change pod reloads, and the resource-metrics API.
