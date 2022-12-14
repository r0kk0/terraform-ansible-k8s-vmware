resource "vsphere_virtual_machine" "server" {
  for_each = var.virtual_machines

  name             = each.key
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  guest_id         = "ubuntu64Guest"
  num_cpus               = each.value.system_cores
  num_cores_per_socket   = each.value.system_cores_per_socket
  cpu_hot_add_enabled    = true
  cpu_hot_remove_enabled = true
  memory                 = each.value.system_memory
  memory_hot_add_enabled = true
  enable_disk_uuid = true

  cdrom {
    client_device = true
  }
  
  vapp {
    properties = {
      "instance-id" = each.key
      "hostname"    = each.key
      "user-data"   = data.template_cloudinit_config.configurazione[each.key].rendered
    }
  }

  network_interface {
    network_id   = data.vsphere_network.network.id
  }

  disk {
    label            = "disk0"
    unit_number      = 0
    size             = 80
    thin_provisioned = true
  }

  clone {
      template_uuid = data.vsphere_virtual_machine.kubetemplate.id
      customize {
          linux_options {
              host_name = each.key
              domain = "r0kk0.casa"
          }
          network_interface {
              ipv4_address = each.value.system_ipv4_address
              ipv4_netmask = each.value.system_ipv4_netmask
          }
          ipv4_gateway = each.value.system_ipv4_gateway
          dns_server_list = ["172.25.0.10"]
          dns_suffix_list = ["r0kk0.casa"]
      }
  }
}

resource "null_resource" ansible {

  provisioner "local-exec" {
    command = "ansible-playbook -i playbook/inventory playbook/k8s-bootstrap.yml" 
  }

  depends_on = [
    vsphere_virtual_machine.server
  ]
}


resource "null_resource" kiratechtest {

  provisioner "local-exec" {
    command = "KUBECONFIG=./playbook/admin.conf kubectl create namespace kiratech-test"
  }

  depends_on = [
    null_resource.ansible
  ]
}

resource "null_resource" labels {

  provisioner "local-exec" {
    command = "KUBECONFIG=./playbook/admin.conf kubectl label node node1 node-role.kubernetes.io/worker=worker"
  }

  provisioner "local-exec" {
    command = "KUBECONFIG=./playbook/admin.conf kubectl label node node2 node-role.kubernetes.io/worker=worker"
  }

  depends_on = [
    null_resource.ansible
  ]
}

resource "null_resource" kubebench {

  provisioner "local-exec" {
    command = "KUBECONFIG=./playbook/admin.conf kubectl apply -f kube-bench.yml"
  }

  depends_on = [
    null_resource.ansible
  ]
}
