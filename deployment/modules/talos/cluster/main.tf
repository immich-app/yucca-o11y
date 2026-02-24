module "node" {
  source   = "./modules/node"
  for_each = var.nodes

  node_key           = each.key
  node               = each.value
  node_ip            = var.node_ips[each.key]
  env                = var.env
  talos_version      = var.talos_version
  talos_schematic_id = var.talos_schematic_id
}

moved {
  from = talos_machine_secrets.nodes["lon"]
  to   = module.node["lon"].talos_machine_secrets.this
}
moved {
  from = talos_machine_secrets.nodes["rbx"]
  to   = module.node["rbx"].talos_machine_secrets.this
}
moved {
  from = talos_machine_secrets.nodes["fra"]
  to   = module.node["fra"].talos_machine_secrets.this
}

moved {
  from = talos_machine_configuration_apply.nodes["lon"]
  to   = module.node["lon"].talos_machine_configuration_apply.this
}
moved {
  from = talos_machine_configuration_apply.nodes["rbx"]
  to   = module.node["rbx"].talos_machine_configuration_apply.this
}
moved {
  from = talos_machine_configuration_apply.nodes["fra"]
  to   = module.node["fra"].talos_machine_configuration_apply.this
}

moved {
  from = talos_machine_bootstrap.nodes["lon"]
  to   = module.node["lon"].talos_machine_bootstrap.this
}
moved {
  from = talos_machine_bootstrap.nodes["rbx"]
  to   = module.node["rbx"].talos_machine_bootstrap.this
}
moved {
  from = talos_machine_bootstrap.nodes["fra"]
  to   = module.node["fra"].talos_machine_bootstrap.this
}

moved {
  from = talos_cluster_kubeconfig.nodes["lon"]
  to   = module.node["lon"].talos_cluster_kubeconfig.this
}
moved {
  from = talos_cluster_kubeconfig.nodes["rbx"]
  to   = module.node["rbx"].talos_cluster_kubeconfig.this
}
moved {
  from = talos_cluster_kubeconfig.nodes["fra"]
  to   = module.node["fra"].talos_cluster_kubeconfig.this
}

moved {
  from = tailscale_tailnet_key.nodes["lon"]
  to   = module.node["lon"].tailscale_tailnet_key.this
}
moved {
  from = tailscale_tailnet_key.nodes["rbx"]
  to   = module.node["rbx"].tailscale_tailnet_key.this
}
moved {
  from = tailscale_tailnet_key.nodes["fra"]
  to   = module.node["fra"].tailscale_tailnet_key.this
}
