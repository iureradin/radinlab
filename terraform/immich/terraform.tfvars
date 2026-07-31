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

# --- Photo Storage (500GB from 4TB disk)
photos_mount_volume = "/dev/sdb1"
photos_mount_path   = "/mnt/photos"
photos_mount_size   = "500G"

# --- Network
network_bridge = "vmbr0"
ipv4_address   = "dhcp"

# --- Immich
immich_version = "release"
