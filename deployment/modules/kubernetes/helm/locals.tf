locals {
  other_node_ips = {
    for k, v in var.clusters : k => [
      for ok in sort(keys(var.clusters)) : var.clusters[ok].tailscale_ip
      if ok != k
    ]
  }
}
