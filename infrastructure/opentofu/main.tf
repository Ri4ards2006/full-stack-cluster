# ==============================================================================
# OpenTofu / Terraform Configuration for Cloud Witness Node (Hetzner Cloud)
# Ensures 3-Node Quorum for embedded etcd high availability.
# ==============================================================================

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.48.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

# Optional SSH Key registration
resource "hcloud_ssh_key" "default" {
  count      = var.ssh_public_key != "" ? 1 : 0
  name       = "k3s-witness-ssh-key"
  public_key = var.ssh_public_key
}

# Cloud Witness Node Instance
resource "hcloud_server" "k3s_witness" {
  name        = "cloud-witness"
  image       = "debian-12"
  server_type = var.server_type
  location    = var.location
  ssh_keys    = var.ssh_public_key != "" ? [hcloud_ssh_key.default[0].id] : []

  # Injected Cloud-Init template for zero-touch Tailscale & K3s etcd join
  user_data = templatefile("${path.module}/cloud-init.yaml", {
    tailscale_auth_key = var.tailscale_auth_key
    k3s_master_ip      = var.k3s_master_ip
    k3s_cluster_token  = var.k3s_cluster_token
  })

  labels = {
    "role"        = "witness"
    "cluster"     = "full-stack-cluster"
    "environment" = "homelab-hybrid"
  }
}

