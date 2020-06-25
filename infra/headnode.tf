terraform {
  required_version = ">= 0.12, < 0.13"
}

# https://www.terraform.io/docs/providers/openstack/index.html
# uses clouds.yml
provider "openstack" {
  cloud = local.config.cloud.name
  version = "~> 1.25"
}

data "external" "tf_control_hostname" {
  program = ["../tf_scripts/gethost.sh"]
}

locals {
  config = yamldecode(file("../config/deploy.yml"))
  tf_dir = "${data.external.tf_control_hostname.result.hostname}:${path.cwd}"
}

resource "openstack_compute_instance_v2" "login" {

  count = local.config.cluster.login.num_nodes

  name = "${local.config.cluster.name}-login-${count.index}"
  image_name = local.config.cluster.login.image
  flavor_name = local.config.cluster.login.flavor
  key_pair = local.config.cluster.keypair
  config_drive = local.config.cluster.login.config_drive

  dynamic "network" {
    for_each = local.config.cluster.login.networks

    content {
      name = network.value
    }
  }
  
  metadata = {
    "terraform directory" = local.tf_dir,
    "cluster" = local.config.cluster.name
  }
}


# TODO: probably needs fixing for multiple control/login nodes
# TODO: needs fixing for case where creation partially fails resulting in "compute.network is empty list of object"
resource "local_file" "hosts" {
  content  = templatefile("${path.module}/inventory_head.tpl",
                          {
                            "config":local.config,
                            "logins":openstack_compute_instance_v2.login,
                          },
                          )
  filename = "${path.module}/../inventory/inventory_head.ini"
}

output "login_ip_addr" {
  value = openstack_compute_instance_v2.login[0].network[0].fixed_ip_v4
}