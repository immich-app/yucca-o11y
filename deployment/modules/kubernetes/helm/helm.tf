module "cluster" {
  source   = "./modules/cluster"
  for_each = var.clusters

  providers = {
    helm       = helm.cluster[each.key]
    kubernetes = kubernetes.cluster[each.key]
  }

  cluster_name              = each.value.name
  flux_operator_version     = var.flux_operator_version
  flux_instance_values_file = "${path.module}/values.yaml"
  env                       = var.env

  other_node_ips                  = local.other_node_ips[each.key]
  vmauth_external_reader_password = random_password.vmauth_external_reader.result
  vmauth_external_writer_password = random_password.vmauth_external_writer.result
  vmauth_internal_reader_password = random_password.vmauth_internal_reader.result
  vmauth_internal_writer_password = random_password.vmauth_internal_writer.result
  ovh_application_key             = var.ovh_application_key
  ovh_application_secret          = var.ovh_application_secret
  ovh_consumer_key                = var.ovh_consumer_key
  op_credentials_file             = var.op_credentials_file
  op_connect_token                = var.op_connect_token
  op_connect_token_env            = var.op_connect_token_env
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
