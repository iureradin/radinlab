terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  node_name = var.node_name
  vm_id     = var.vm_id
  name      = var.name
  on_boot   = var.on_boot

  cpu {
    cores = var.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.datastore_id
    file_id      = var.iso_file_id
    interface    = "ide2"
    size         = 0
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_os_size
  }

  dynamic "disk" {
    for_each = var.disk_data_size > 0 ? [1] : []
    content {
      datastore_id = var.datastore_id
      interface    = "scsi1"
      size         = var.disk_data_size
    }
  }

  network_device {
    bridge = var.network_bridge
  }

  operating_system {
    type = "l26"
  }
}
