module "cluster" {
  source   = "./modules/cluster"
  for_each = var.clusters

  providers = {
    helm       = helm.cluster[each.key]
    kubernetes = kubernetes.cluster[each.key]
  }

  cluster_name              = each.value.name
  flux_operator_version     = var.flux_operator_version
  flux_instance_values_file = "${path.module}/values.yml"

  other_node_ips                 = local.other_node_ips[each.key]
  vmauth_reader_password         = random_password.vmauth_reader.result
  vmauth_writer_password         = random_password.vmauth_writer.result
  vmauth_internal_reader_password = random_password.vmauth_internal_reader.result
  vmagent_password               = random_password.vmagent.result
}

output "cluster_deployments" {
  value = {
    for k, v in module.cluster : k => {
      cluster_name         = v.cluster_name
      flux_operator_status = v.flux_operator_status
      flux_instance_status = v.flux_instance_status
    }
  }
}
