# 1. Proxmox API Authentication Variables

variable "proxmox_api_url" {
  type        = string
  description = "The API endpoint for your Proxmox VE node"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "The Token ID generated in Proxmox (e.g., terraform-user@pve!token_name)"
}

variable "proxmox_api_token_secret" {
  type        = string
  sensitive   = true
  description = "The actual secret key generated alongside the Token ID"
}

variable "proxmox_insecure" {
  type        = bool
  default     = true
  description = "Bypass SSL validation checks for self-signed cluster certificates"
}

# 2. Proxmox Infrastructure & Storage

variable "pve_iso_datastore" {
  type        = string
  default     = "local"
  description = "The Proxmox storage pool where cloud images are downlaoded"
}

variable "pve_vm_datastore" {
  type        = string
  default     = "local-lvm"
  description = "The Proxmox storage pool where VM virtual disks are provisioned"
}

# 3. Compute & Cloud-Init Virtual Machines

variable "os_image_url" {
  type        = string
  default     = "https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2"
  description = "The download URL for Fedora Cloud Init Base OS"
}

variable "os_image_filename" {
  type        = string
  default     = "fedora-cloud-base.qcow2"
  description = "Filename assigned to the downloaded OS image"
}

variable "vm_disk_size" {
  type        = number
  default     = 30    # This is a very low number and to properly set this up you will need more. This is only for testing as of now.
  description = "Root operating system disk allotment size in GB"
}

variable "ssh_username" {
  type        = string
  default     = "stoof" # Be sure to change this to whatever you want it to be.
  description = "Primary admin sudo username built inside the OS"
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "Array of authorized public keys allowed to log into the nodes"
}

# 4. Networking & Kubernetes Topology

variable "network_gateway" {
  type        = string
  description = "The network gateway IP for you internet facing router (eg. 192.168.0.1)"
}

variable "network_bridge" {
  type        = string
  default     = "vmbr0"
  description = "Network bridge assigned to the physical Promox network interface that is internet facing"
}

variable "k8s_nodes" {
  type = map(object({
    node      = string
    vmid      = number
    ip        = string
    cores     = number
    memory    = number
  }))
  description = "Map of Kubernetes cluster topologies containing hardware specifications"
}
