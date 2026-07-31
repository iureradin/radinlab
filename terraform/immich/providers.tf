# ---
# Immich - Provider Configuration
# ---

provider "proxmox" {
  endpoint = var.proxmox_api_url
  insecure = var.proxmox_insecure

  api_token = var.proxmox_api_token
}
