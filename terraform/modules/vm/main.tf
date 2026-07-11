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
  bios      = var.bios

  agent {
    enabled = var.agent_enabled
  }

  dynamic "clone" {
    for_each = var.clone_vm_id != null ? [1] : []
    content {
      vm_id = var.clone_vm_id
      full  = true
    }
  }

  cpu {
    cores = var.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.memory
  }

  dynamic "cdrom" {
    for_each = var.iso_file_id != null ? [1] : []
    content {
      file_id   = var.iso_file_id
      interface = "ide2"
    }
  }

  dynamic "disk" {
    for_each = var.clone_vm_id == null ? [1] : []
    content {
      datastore_id = var.datastore_id
      interface    = "scsi0"
      size         = var.disk_os_size
    }
  }

  dynamic "disk" {
    for_each = var.clone_vm_id == null && var.disk_data_size > 0 ? [1] : []
    content {
      datastore_id = var.datastore_id
      interface    = "scsi1"
      size         = var.disk_data_size
    }
  }

  dynamic "efi_disk" {
    for_each = var.bios == "ovmf" && var.clone_vm_id == null ? [1] : []
    content {
      datastore_id = var.datastore_id
    }
  }

  network_device {
    bridge      = var.network_bridge
    mac_address = var.mac_address
  }

  operating_system {
    type = "l26"
  }
}
