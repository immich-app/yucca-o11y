# Bootstrap guide

How to stand up an environment from nothing. The cluster is built by Terragrunt in module order, then handed to Flux. Run everything through `mise` so tool versions and 1Password credential injection are consistent. See the [README](../README.md) for the repository layout — where each module and manifest lives, and where state and secrets come from.

## One-time prep (per environment)

1. Create the environment's 1Password vault (`o11y_tf_staging` or `o11y_tf_prod`).
2. Set up `.private/openstack/<env>/openrc.sh` for the environment's OVH Public Cloud project.
3. Upload the Talos **OpenStack** image (control planes only) to the environment's regions:

   ```bash
   mise run talos:dl:cp && mise run talos:ul:cp
   ```

   This image carries the `qemu-guest-agent` + `netbird` schematic.
4. Workers need **no download or upload** — they are OVH BYOI and pull the bare-metal raw straight from the Talos Factory at order time. The worker schematic must stay **netbird-only**: `qemu-guest-agent` on bare metal blocks on a virtio port that never appears and reboot-loops the node.
5. For production: delete the apex DNS records via the OVH dashboard before applying.

## Apply order

Set the environment in the shell first:

```bash
export ENVIRONMENT=staging
export TF_VAR_env=staging
```

1. **OVH** — cloud project, vRack, private network, CP instances, workers, IPLB, DNS. First-time runs are slow (CP instances ~5 min each, bare-metal orders 20–45 min each, IPLB ~10 min).

   ```bash
   mise run tg run --working-dir deployment/modules/ovh/account apply
   ```

2. **NetBird** — the per-environment mesh objects: the Talos node group, a reusable setup key, the vRack network route (Talos nodes as routing peers), and the `yucca → resource` access policy. The Talos module consumes the setup key from here, so apply NetBird first.

   ```bash
   mise run tg run --working-dir deployment/modules/netbird/cluster apply
   ```

3. **Talos (bootstrap)** — initial bring-up over public IPs, because the NetBird extension isn't running yet.

   ```bash
   TF_VAR_use_public_endpoints=true mise run tg run --working-dir deployment/modules/talos/cluster apply
   ```

4. **Verify** the cluster is up and operator-side NetBird routing works. Pull the configs (see [Cluster access](#cluster-access)) and hit the APIs over the NetBird network:

   ```bash
   mise run talos:kubeconfig && mise run talos:talosconfig
   kubectl --kubeconfig .private/$ENVIRONMENT/kubeconfig get nodes -o wide
   talosctl --talosconfig .private/$ENVIRONMENT/talosconfig -n 10.150.200.10 get members
   ```

5. **Talos (steady state)** — drop the public-endpoints override now that NetBird routes work; the host firewall closes the public NIC (everything except `:30443` on workers).

   ```bash
   unset TF_VAR_use_public_endpoints
   mise run tg run --working-dir deployment/modules/talos/cluster apply
   ```

6. **Kubernetes/Helm** — install the Flux Operator + Instance and create bootstrap secrets (cert-manager, OVH DNS credentials, external-secrets 1Password token). After this, Flux owns cluster state.

   ```bash
   mise run tg run --working-dir deployment/modules/kubernetes/helm apply
   ```

Flux then reconciles from `kubernetes/clusters/<env>/apps.yaml`, fanning out to the per-app Kustomizations in dependency order.

## Cluster access

How to get `kubectl` / `talosctl` access to an **existing** cluster (no bootstrap required).

**Prerequisites:**

* **NetBird** — the cluster APIs are reachable only over the NetBird network, so your host must be running the NetBird client (`netbird up`) and joined to the FUTO NetBird account, which places your peer in the `yucca` group. The access policy then distributes the route to the cluster's vRack CIDR, so `kubectl`/`talosctl` can reach the nodes' private IPs.
* **1Password CLI (`op`)** — installed and signed in to the `team-futo.1password.com` account. `mise run talos:config` fetches the configs through `mise run tg`, which wraps `op run` to inject the Terraform state credentials; without an authenticated `op` it can't read state.

**Fetch the configs.** Two tasks pull `kubeconfig` and `talosconfig` for the environment (run whichever you need):

```bash
export ENVIRONMENT=staging        # or production
export TF_VAR_env=$ENVIRONMENT
mise run talos:kubeconfig         # for kubectl
mise run talos:talosconfig        # for talosctl
```

Each writes to `.private/$ENVIRONMENT/` (mode 600) from the Talos module's Terraform outputs. The kubeconfig is TF-authored with two contexts:

* **`o11y-<env>`** (default) — the HA endpoint `kube.<mesh-zone>:6443`, fronted by the Envoy mesh gateway (TLS passthrough to every apiserver). Survives any single CP being down and never hairpins through a NetBird routing peer.
* **`o11y-<env>-direct`** — a control-plane private IP, for bootstrap/DR before the mesh gateway exists: `kubectl --context o11y-<env>-direct`. Every CP IP is an apiserver cert SAN, so TLS validates on both paths. (The floating VIP `.5` is in-cluster-only — it doesn't ARP across DCs.)

**Point your tools at them:**

```bash
export KUBECONFIG=$PWD/.private/$ENVIRONMENT/kubeconfig
export TALOSCONFIG=$PWD/.private/$ENVIRONMENT/talosconfig

kubectl get nodes
talosctl -n 10.150.200.10 health   # any CP private IP; the talosconfig also lists the workers
```

## Common operations

| Task | Command |
| --- | --- |
| Plan/apply one module | `mise run tg run --working-dir deployment/modules/<m> {plan,apply}` |
| Plan/apply all in dep order | `mise run tf:{plan,apply}` |
| Re-init backends | `mise run tf:init` |
| Format HCL / Terraform | `mise run tg:fmt` / `mise run tf:fmt` |
| Lint docs | `mise run md:lint` |
| Fetch kubeconfig / talosconfig | `mise run talos:kubeconfig` / `mise run talos:talosconfig` (see [Cluster access](#cluster-access)) |

## Tooling

* **OpenTofu** + **Terragrunt** for IaC; **mise** drives tool versions and task wrappers. Version pins live in `.mise/config.toml` and each module's lock file.
* **1Password CLI** (`op run --env-file deployment/.env`) injects API credentials at invocation time.
