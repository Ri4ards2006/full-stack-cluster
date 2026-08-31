# ==============================================================================
# OpenTofu Outputs
# ==============================================================================

output "witness_server_id" {
  description = "Unique ID of the provisioned Hetzner Cloud witness server"
  value       = hcloud_server.k3s_witness.id
}

output "witness_public_ip" {
  description = "Public IPv4 address of the witness server"
  value       = hcloud_server.k3s_witness.ipv4_address
}

output "witness_status" {
  description = "Execution status of the witness server"
  value       = hcloud_server.k3s_witness.status
}
