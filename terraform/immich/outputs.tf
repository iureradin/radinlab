# ---
# Immich - Outputs
# ---

output "container_id" {
  description = "The VM ID of the Immich container"
  value       = module.immich_container.container_id
}

output "container_node_name" {
  description = "The Proxmox node the container is running on"
  value       = module.immich_container.container_node_name
}

output "container_status" {
  description = "The current status of the container"
  value       = module.immich_container.container_status
}
