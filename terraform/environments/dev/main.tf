module "zimaos" {
  source = "../../modules/vm"

  node_name      = "pve"
  vm_id          = 105
  name           = "zimaos"
  cpu_cores      = 2
  memory         = 4096
  disk_os_size   = 30
  disk_data_size = 40
  datastore_id   = "local-lvm"
  iso_file_id    = "local:iso/zimaos-1.6.1.iso"
  network_bridge = "vmbr0"
  on_boot        = true
}

