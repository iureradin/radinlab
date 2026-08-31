# ---
# Immich - Main Configuration
# Deploys Immich Photo Management on Proxmox LXC
# ---

module "immich_container" {
  source = "git::https://github.com/iureradin/terraform-proxmox-lxc.git?ref=v1.0.0"

  # --- General
  target_node = var.proxmox_node
  vmid        = var.container_vmid
  hostname    = var.container_hostname
  description = var.container_description
  tags        = var.container_tags

  # --- Operating System
  os_template = var.os_template

  # --- Resources
  cpu_cores         = var.cpu_cores
  memory_mb         = var.memory_mb
  root_datastore    = var.root_datastore
  root_disk_size_gb = var.root_disk_size_gb

  # --- Network
  network_bridge = var.network_bridge
  ipv4_address   = var.ipv4_address

  # --- Authentication
  ssh_public_keys = var.ssh_public_keys
  root_password   = var.root_password

  # --- Features (Docker support)
  # keyctl não pode ser definido via API token — será adicionado via SSH no provision step
  enable_nesting = true
  enable_keyctl  = false
  unprivileged   = true

  # --- Boot
  start_on_boot = true
}
