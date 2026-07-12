variable "proxmox_endpoint" {
  description = "URL da API do Proxmox"
  type        = string
}

variable "proxmox_api_token" {
  description = "Token de API do Proxmox"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Nome do node Proxmox"
  type        = string
  default     = "pve"
}
