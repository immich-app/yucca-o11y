# Bootstrap guide

How to stand up an environment from nothing. The cluster is built by Terragrunt in module order, then handed to Flux. Run everything through `mise` so tool versions and 1Password credential injection are consistent. See the [README](../README.md) for the repository layout — where each module and manifest lives, and where state and secrets come from.

## One-time prep (per environment)

1. Create the environment's 1Password vault (`o11y_tf_staging` or `o11y_tf_prod`).
2. Set up `.private/openstack/<env>/openrc.sh` for the environment's OVH Public Cloud project.
3. Upload the Talos **OpenStack** image (control planes only) to the environment's regions:

   ```bash
   mise run talos:dl:cp && mise run talos:ul:cp
   ```

   This image carries the `qemu-guest-agent` + `tailscale` schematic.
4. Workers need **no download or upload** — they are OVH BYOI and pull the bare-metal raw straight from the Talos Factory at order time. The worker schematic must stay **tailscale-only**: `qemu-guest-agent` on bare metal blocks on a virtio port that never appears and reboot-loops the node.
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

2. **Tailscale** — tailnet-global ACL (only needs one run across all environments).

   ```bash
   mise run tg run --working-dir deployment/modules/tailscale/account apply
   ```

3. **Talos (bootstrap)** — initial bring-up over public IPs, because the Tailscale extension isn't running yet.

   ```bash
   TF_VAR_use_public_endpoints=true mise run tg run --working-dir deployment/modules/talos/cluster apply
   ```

4. **Verify** the cluster is up and operator-side Tailscale routing works.

   ```bash
   mkdir -p .private/$ENVIRONMENT
   mise run tg run --working-dir deployment/modules/talos/cluster output -- -raw talos_client_configuration > .private/$ENVIRONMENT/talosconfig
   mise run tg run --working-dir deployment/modules/talos/cluster output -- -raw kubeconfig > .private/$ENVIRONMENT/kubeconfig
   chmod 600 .private/$ENVIRONMENT/{talosconfig,kubeconfig}
   # Pick any CP private IP — they're all valid cert SANs.
   CP_IP=10.150.200.10
   talosctl --talosconfig .private/$ENVIRONMENT/talosconfig --endpoints $CP_IP --nodes $CP_IP get members
   sd -F "server: https://10.150.200.5:6443" "server: https://$CP_IP:6443" .private/$ENVIRONMENT/kubeconfig
   kubectl --kubeconfig .private/$ENVIRONMENT/kubeconfig get nodes -o wide
   ```

5. **Talos (steady state)** — drop the public-endpoints override now that Tailscale routes work; the host firewall closes the public NIC (everything except `:30443` on workers).

   ```bash
   unset TF_VAR_use_public_endpoints
   mise run tg run --working-dir deployment/modules/talos/cluster apply
   ```

6. **Kubernetes/Helm** — install the Flux Operator + Instance and create bootstrap secrets (cert-manager, OVH DNS credentials, external-secrets 1Password token). After this, Flux owns cluster state.

   ```bash
   mise run tg run --working-dir deployment/modules/kubernetes/helm apply
   ```

Flux then reconciles from `kubernetes/clusters/<env>/apps.yaml`, fanning out to the per-app Kustomizations in dependency order.

## Operator access

Tailscale must be running on the operator's host with subnet-route consumption enabled (`tailscale set --accept-routes` on Linux; the macOS GUI "Use Tailscale subnets" toggle). Then:

* **kubectl** — the kubeconfig's default `server:` is the cluster VIP, which works in-cluster but is unreliable from outside. Rewrite it to a CP private IP (every CP IP is in the apiserver cert SANs, so TLS validates):

  ```bash
  sd -F 'https://10.150.200.5:6443' 'https://10.150.200.10:6443' .private/staging/kubeconfig
  ```

* **talosctl** — endpoints are already CP private IPs after the steady-state step; the talosconfig also includes worker private IPs for direct node access.

## Common operations

| Task | Command |
| --- | --- |
| Plan/apply one module | `mise run tg run --working-dir deployment/modules/<m> {plan,apply}` |
| Plan/apply all in dep order | `mise run tf:{plan,apply}` |
| Re-init backends | `mise run tf:init` |
| Format HCL / Terraform | `mise run tg:fmt` / `mise run tf:fmt` |
| Lint docs | `mise run md:lint` |
| Pull current kubeconfig | `mise run tg run --working-dir deployment/modules/talos/cluster output -- -raw kubeconfig > .private/$ENVIRONMENT/kubeconfig` |

## Tooling

* **OpenTofu** + **Terragrunt** for IaC; **mise** drives tool versions and task wrappers. Version pins live in `.mise/config.toml` and each module's lock file.
* **1Password CLI** (`op run --env-file deployment/.env`) injects API credentials at invocation time.
