terraform {
  cloud {
    # Remember to swap this to match your exact HCP orgination name.
    organization = "stoof-homelab"

    workspaces {
      name = "stoof-lab"
    }
  }
}

# 1. Automatically download the Fedora Cloud Base Image onto your nodes
resource "proxmox_download_file" "fedora_cloud_image" {
  for_each            = toset([for k, v in var.k8s_nodes : v.node])
  content_type        = "import"
  datastore_id        = var.pve_iso_datastore
  node_name           = each.key
  url                 = var.os_image_url
  file_name           = var.os_image_filename
  overwrite           = true
  overwrite_unmanaged = true
}

# 2. Provision the actual Kubernetes Virtual Machines
resource "proxmox_virtual_environment_vm" "k8s_nodes" {
  for_each        = var.k8s_nodes
  name            = each.key
  node_name       = each.value.node
  vm_id           = each.value.vmid

  stop_on_destroy = true

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  agent {
    enabled = true
  }

  disk {
    datastore_id  = var.pve_vm_datastore
    interface     = "scsi0"
    size          = var.vm_disk_size
    import_from   = proxmox_download_file.fedora_cloud_image[each.value.node].id
  }

  initialization {
    datastore_id = var.pve_vm_datastore
    upgrade = false

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = var.network_gateway
      }
    }

    dns {
      servers = ["192.168.0.1", "1.1.1.1"]
    }

    user_account {
      username = var.ssh_username
      keys     = var.ssh_public_keys
    }
  }

  network_device {
    bridge = var.network_bridge
  }
}
