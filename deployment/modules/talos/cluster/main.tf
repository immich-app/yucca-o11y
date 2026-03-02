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
