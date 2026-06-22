module "zimaos" {
  source = "../../modules/vm"

  node_name      = "pve"
  vm_id          = 106
  name           = "zimaos"
  clone_vm_id    = 105
  cpu_cores      = 2
  memory         = 4096
  disk_os_size   = 30
  disk_data_size = 40
  datastore_id   = "local-lvm"
  network_bridge = "vmbr0"
  mac_address    = "BC:24:11:AA:BB:CC"
  on_boot        = true
  bios           = "ovmf"
  agent_enabled  = false
}
