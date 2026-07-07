variable "proxmox_api_url" {
type = string
description = "The API endpoint for your Proxmox VE node"
}

variable "proxmox_api_token_id" {
type = string
description = "The Token ID generated in Proxmox (e.g., terraform-user@pve!token_name)"
}

variable "proxmox_api_token_secret" {
type = string
sensitive = true
description = "The actual secret key generated alongside the Token ID"
}
