# ---
# Immich - Provider Configuration
# Authentication via environment variables:
#   PROXMOX_VE_ENDPOINT  = https://naruto.local:8006
#   PROXMOX_VE_API_TOKEN = user@realm!tokenid=secret
# ---

provider "proxmox" {
  endpoint = var.proxmox_api_url
  insecure = var.proxmox_insecure

  api_token = var.proxmox_api_token
}
