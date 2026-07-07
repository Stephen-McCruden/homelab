# 1. Define your exact Kubernetes cluster topology map
locals {
k8s_nodes = {
"k8s-worker-01" = { node = "pve1", vmid = 201, ip = "192.168.0.50/24", cores = 4, memory = 8192 }
"k8s-worker-02" = { node = "pve2", vmid = 202, ip = "192.168.0.51/24", cores = 4, memory = 8192 }
"k8s-master-01" = { node = "pve3", vmid = 203, ip = "192.168.0.52/24", cores = 4, memory = 8192 }
}
}

# 2. Automatically download the Fedora Cloud Base Image onto your nodes
resource "proxmox_download_file" "fedora_cloud_image" {
for_each = toset([for k, v in local.k8s_nodes : v.node])
content_type = "import"
datastore_id = "local"
node_name = each.key

url = "https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2"
file_name = "fedora-cloud-base.qcow2"

overwrite           = true
overwrite_unmanaged = true
}

# 4. Provision the actual Kubernetes Virtual Machines
resource "proxmox_virtual_environment_vm" "k8s_nodes" {
for_each = local.k8s_nodes
name = each.key
node_name = each.value.node
vm_id = each.value.vmid

stop_on_destroy = true

cpu {
cores = each.value.cores
type = "host"
}

memory {
dedicated = each.value.memory
}

agent {
enabled = true
}

disk {
datastore_id = "local-lvm" # <-- Ensure your PVE node storage is named this!
interface = "scsi0"
size = 30
import_from = proxmox_download_file.fedora_cloud_image[each.value.node].id
}

initialization {
datastore_id = "local-lvm"

ip_config {
ipv4 {
address = each.value.ip
gateway = "192.168.0.1"
}
}

user_account {
username = "stoof"
keys = [trimspace(file("~/.ssh/id_rsa.pub"))]
}
}

network_device {
bridge = "vmbr0"
}
}
