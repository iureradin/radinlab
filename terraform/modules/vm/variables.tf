variable "node_name" {
  type = string
}

variable "vm_id" {
  type = number
}

variable "name" {
  type = string
}

variable "cpu_cores" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 4096
}

variable "disk_os_size" {
  type    = number
  default = 30
}

variable "disk_data_size" {
  type    = number
  default = 0
}

variable "datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "iso_file_id" {
  type    = string
  default = null
}

variable "clone_vm_id" {
  type    = number
  default = null
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "on_boot" {
  type    = bool
  default = true
}

variable "bios" {
  type    = string
  default = "seabios"
}

variable "agent_enabled" {
  type    = bool
  default = true
}
