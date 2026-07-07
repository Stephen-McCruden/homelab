terraform {
required_version = ">= 1.5.0"
required_providers {
proxmox = {
source = "bpg/proxmox"
version = ">= 0.60.0"
}
}
}

provider "proxmox" {
endpoint = var.proxmox_api_url
api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
insecure = true # Set to true if you use self-signed SSL certificates on your PVE GUI

ssh {
agent = true
# The provider needs SSH access to the Proxmox host itself to inject Cloud-Init data
username = "root"
}
}
