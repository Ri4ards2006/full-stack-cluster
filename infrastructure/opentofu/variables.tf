# ==============================================================================
# OpenTofu / Terraform Input Variables for Cloud Witness Node
# ==============================================================================

variable "hcloud_token" {
  description = "Hetzner Cloud API Token"
  type        = string
  sensitive   = true
}

variable "server_type" {
  description = "Cloud server instance type (minimal footprint for etcd witness)"
  type        = string
  default     = "cx22"
}

variable "location" {
  description = "Datacenter region (e.g. fsn1, nbg1, hel1)"
  type        = string
  default     = "fsn1"
}

variable "ssh_public_key" {
  description = "SSH public key for root administration"
  type        = string
  default     = ""
}

variable "tailscale_auth_key" {
  description = "Tailscale One-Time or Reusable Auth Key"
  type        = string
  sensitive   = true
}

variable "k3s_master_ip" {
  description = "Tailscale IP of primary K3s master node"
  type        = string
  default     = "100.x.y.z"
}

variable "k3s_cluster_token" {
  description = "K3s cluster token for server/agent joining"
  type        = string
  sensitive   = true
}

