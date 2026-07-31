# ---
# Immich - Variables
# ---

# --- Proxmox Connection
variable "proxmox_api_url" {
  description = "Proxmox API endpoint URL"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token (format: user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for Proxmox API"
  type        = bool
  default     = true
}

# --- Container General
variable "proxmox_node" {
  description = "Proxmox node to deploy the container on"
  type        = string
  default     = "pve"
}

variable "container_vmid" {
  description = "VM ID for the container (0 = auto-assign)"
  type        = number
  default     = 0
}

variable "container_hostname" {
  description = "Hostname for the Immich container"
  type        = string
  default     = "immich"
}

variable "container_description" {
  description = "Description of the container"
  type        = string
  default     = "Immich Photo Management - Managed by Terraform"
}

variable "container_tags" {
  description = "Tags to assign to the container"
  type        = list(string)
  default     = ["immich", "docker", "terraform"]
}

# --- Operating System
variable "os_template" {
  description = "Path to the OS template on Proxmox storage"
  type        = string
  default     = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
}

# --- Resources
variable "cpu_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 4
}

variable "memory_mb" {
  description = "Memory in megabytes"
  type        = number
  default     = 8192
}

variable "root_datastore" {
  description = "Datastore for the root disk"
  type        = string
  default     = "local-lvm"
}

variable "root_disk_size_gb" {
  description = "Root disk size in gigabytes"
  type        = number
  default     = 50
}

# --- Photo Storage
variable "photos_mount_volume" {
  description = "Volume for photo storage mount point"
  type        = string
  default     = "/dev/sdb1"
}

variable "photos_mount_path" {
  description = "Mount path inside container for photos"
  type        = string
  default     = "/mnt/photos"
}

variable "photos_mount_size" {
  description = "Size of the photos mount point"
  type        = string
  default     = "500G"
}

# --- Network
variable "network_bridge" {
  description = "Proxmox bridge to attach the network interface"
  type        = string
  default     = "vmbr0"
}

variable "ipv4_address" {
  description = "IPv4 address for the container (use 'dhcp' for DHCP)"
  type        = string
  default     = "dhcp"
}

# --- Authentication
variable "ssh_public_keys" {
  description = "SSH public keys for root access"
  type        = list(string)
  default     = []
}

variable "root_password" {
  description = "Root password for the container"
  type        = string
  sensitive   = true
  default     = null
}

# --- Immich
variable "immich_version" {
  description = "Immich Docker image version tag"
  type        = string
  default     = "release"
}
