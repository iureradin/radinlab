terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.78.0"
    }
  }

  backend "s3" {
    bucket = "radinlab-terraform-state"
    key    = "npm/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true
}

resource "proxmox_virtual_environment_container" "npm" {
  node_name   = var.proxmox_node
  description = "Nginx Proxy Manager"
  tags        = ["npm", "managed-by-terraform"]

  operating_system {
    template_file_id = "local:vztmpl/${var.template_name}"
    type             = "ubuntu"
  }

  initialization {
    hostname = "npm"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    size         = 10
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  features {
    nesting = true
  }

  started = true
}

output "npm_container_id" {
  value = proxmox_virtual_environment_container.npm.vm_id
}
