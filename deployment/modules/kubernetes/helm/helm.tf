module "cluster" {
  source   = "./modules/cluster"
  for_each = var.clusters

  providers = {
    helm = helm.cluster[each.key]
  }

  cluster_name              = each.value.name
  flux_operator_version     = var.flux_operator_version
  flux_instance_values_file = "${path.module}/values.yml"
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
