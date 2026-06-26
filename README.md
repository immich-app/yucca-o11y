# Yucca O11y

The centralized observability platform for FUTO services. A single Talos Kubernetes cluster per environment, stretched across multiple OVH datacentres and managed by Flux. It hosts the metrics, dashboards, and alerting stack, and is the **central metrics store** that other FUTO clusters remote-write into.

Built for geographic resilience with single-cluster operational simplicity: three control planes in low-latency DCs hold one etcd quorum, three bare-metal workers carry the observability workload, and everything talks over a private OVH vRack.

**Status:** staging is built and running (`o11y-staging`); production is planned (`o11y-production`).

## Documentation

| Guide | Covers |
| --- | --- |
| [01 — Bootstrap](./docs/01-bootstrap-guide.md) | Standing up an environment: one-time prep, Terragrunt apply order, operator access, common operations |
| [02 — Infrastructure architecture](./docs/02-infrastructure-architecture-guide.md) | OVH compute, hardware specs, vRack networking, IPLB ingress, cost |
| [03 — Cluster architecture](./docs/03-cluster-architecture-guide.md) | Talos, Kubernetes, host firewall, and Flux GitOps |
| [04 — Application architecture](./docs/04-application-architecture-guide.md) | Envoy ingress, VictoriaMetrics central store, Grafana, CloudNativePG, supporting operators |

## Repository layout

```text
deployment/modules/
├── ovh/account/          # cloud project, vRack, private network, CPs, workers, IPLB, DNS
├── tailscale/account/    # tailnet-global ACL and tailnet settings
├── talos/cluster/        # machine secrets, CP + worker configs, bootstrap, ingress firewall
└── kubernetes/helm/      # Flux Operator + Instance, env-scoped secrets

kubernetes/
├── apps/
│   ├── base/             # chart sources + reusable manifests
│   └── <env>/            # env overlay: Flux Kustomizations (version pins + dependsOn)
└── clusters/
    └── <env>/
        ├── apps.yaml             # cluster-apps entry point (the Flux Instance points here)
        └── cluster-settings.yaml # per-env ConfigMap: APP_DOMAIN, CLUSTER_NAME
```

State lives in S3 under `yucca/o11y/v3/<module>/<env>`. Secrets and OVH/Tailscale tokens come from the environment's 1Password vault via `op run` and `deployment/.env`.
