# ---
# Immich - Production Variable Values
# ---

# --- Proxmox Connection
# proxmox_api_url comes from TF_VAR_proxmox_api_url (GitHub vars.PROXMOX_ENDPOINT)
proxmox_insecure = true

# --- Container Configuration
proxmox_node          = "naruto"
container_vmid        = 110
container_hostname    = "immich"
container_description = "Immich Photo Management - Managed by Terraform"
container_tags        = ["immich", "docker", "terraform"]

# --- Operating System
os_template = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"

# --- Resources
cpu_cores         = 4
memory_mb         = 8192
root_disk_size_gb = 50
root_datastore    = "ssd-vms"

# --- Photo Storage (bind mount added post-provision via pct config)
# Host: /mnt/hd4tb/immich -> Container: /mnt/photos (same pattern as Jellyfin)

# --- Network
network_bridge = "vmbr0"
ipv4_address   = "10.0.0.76/8"

# --- Photo Storage (bind mount adicionado pós-provision via pct config)
# Host: /mnt/hd1tb/iure/fotos -> CT: /mnt/fotos (ro) -> Docker: /mnt/hd1tb/iure/fotos (ro)

# --- Immich
immich_version = "v3"
