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

variable "template_name" {
  description = "Nome do template LXC (deve existir em local:vztmpl/)"
  type        = string
  default     = "ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}
