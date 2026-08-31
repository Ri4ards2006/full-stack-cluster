# Declarative K3s Node Configuration

This directory contains declarative configuration templates replacing the legacy runtime bash patching scripts (`fix-cluster-network.sh` and `fix-k3s-dns-persistent.sh`).

## Master (Control Plane) Node Setup
1. Copy the static DNS configuration:
   ```bash
   sudo cp config/k3s/resolv.conf /etc/rancher/k3s/resolv.conf
   ```
2. Copy and customize the server configuration:
   ```bash
   sudo cp config/k3s/config.yaml.example /etc/rancher/k3s/config.yaml
   # Edit /etc/rancher/k3s/config.yaml and insert your Tailscale IP
   ```
3. Restart K3s Server:
   ```bash
   sudo systemctl restart k3s
   ```

---

## Worker (Agent) Node Setup
1. Copy the static DNS configuration:
   ```bash
   sudo cp config/k3s/resolv.conf /etc/rancher/k3s/resolv.conf
   ```
2. Copy and customize the agent configuration:
   ```bash
   sudo cp config/k3s/agent-config.yaml.example /etc/rancher/k3s/config.yaml
   # Edit /etc/rancher/k3s/config.yaml with Master Tailscale IP and node token
   ```
3. Restart K3s Agent:
   ```bash
   sudo systemctl restart k3s-agent
   ```
