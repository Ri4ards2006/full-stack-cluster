#!/usr/bin/env bash

# ==============================================================================
# Script: fix-cluster-network.sh
# Description: Production-ready network and firewall optimization script for 
#              K3s multi-node clusters running over Tailscale on Arch Linux.
# Usage: sudo ./fix-cluster-network.sh
# ==============================================================================

set -euo pipefail

# Colors for professional stdout feedback
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 1. Root Privilege Verification
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run with root privileges (sudo)."
   exit 1
fi

log_info "Starting K3s Tailscale network and firewall remediation..."

# 2. Enable IP Forwarding (Kernel Level)
log_info "Configuring sysctl kernel parameters for IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Persist the change across reboots
SYSCTL_CONF="/etc/sysctl.d/99-k3s-networking.conf"
if [[ ! -f "$SYSCTL_CONF" ]] || ! grep -q "net.ipv4.ip_forward" "$SYSCTL_CONF"; then
    echo "net.ipv4.ip_forward = 1" > "$SYSCTL_CONF"
    log_success "Persisted net.ipv4.ip_forward = 1 in $SYSCTL_CONF"
else
    log_info "Kernel forwarding persistence already configured in $SYSCTL_CONF"
fi
sysctl --system >/dev/null

# 3. Dynamic MTU Fix for Flannel Over Tailscale
# Tailscale MTU defaults to 1280. Flannel VXLAN adds 50 bytes of overhead.
# If flannel.1 is left at the default 1450 MTU, packet fragmentation/drops occur.
log_info "Analyzing Flannel MTU configurations..."
if ip link show flannel.1 >/dev/null 2>&1; then
    log_info "flannel.1 interface detected. Tuning MTU to 1230 on-the-fly..."
    ip link set dev flannel.1 mtu 1230
    log_success "flannel.1 MTU temporarily optimized to 1230."
else
    log_warn "flannel.1 interface not found (K3s might not be running yet). Skipping runtime MTU tune."
fi

# 4. Firewall Detection and Remediation
# A. UFW (Uncomplicated Firewall)
if command -v ufw >/dev/null && systemctl is-active --quiet ufw; then
    log_info "Active UFW firewall detected. Applying rules..."
    
    # Enable UFW forwarding policy
    UFW_DEFAULT="/etc/default/ufw"
    if [[ -f "$UFW_DEFAULT" ]]; then
        sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/g' "$UFW_DEFAULT"
        log_success "Set DEFAULT_FORWARD_POLICY to ACCEPT in $UFW_DEFAULT"
    fi

    # Allow interfaces
    ufw allow in on flannel.1 to any >/dev/null
    ufw allow in on tailscale0 to any >/dev/null
    
    # Specific ports over Tailscale as a secondary fallback
    ufw allow in on tailscale0 proto tcp to any port 6443 comment "K3s API Server" >/dev/null
    ufw allow in on tailscale0 proto tcp to any port 10250 comment "Kubelet metrics" >/dev/null
    ufw allow in on tailscale0 proto udp to any port 8472 comment "Flannel VXLAN" >/dev/null
    
    ufw reload >/dev/null
    log_success "UFW rules applied and reloaded."
fi

# B. Firewalld
if command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld; then
    log_info "Active firewalld daemon detected. Applying zone rules..."
    
    # Place interfaces in trusted zone to allow internal cluster routing
    firewall-cmd --permanent --zone=trusted --add-interface=flannel.1 >/dev/null || true
    firewall-cmd --permanent --zone=trusted --add-interface=tailscale0 >/dev/null || true
    
    # Alternatively, ensure forwarding is enabled globally in firewalld configuration
    firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i flannel.1 -j ACCEPT >/dev/null || true
    firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -o flannel.1 -j ACCEPT >/dev/null || true
    firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i tailscale0 -j ACCEPT >/dev/null || true
    firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -o tailscale0 -j ACCEPT >/dev/null || true
    
    firewall-cmd --reload >/dev/null
    log_success "Firewalld rules applied and reloaded."
fi

# C. Raw iptables / nftables translation layer
log_info "Injecting raw iptables forwarding and input rules..."

# Insert forwarding rules at the very top of the FORWARD chain (index 1) to preempt any rejects
iptables -I FORWARD 1 -i flannel.1 -j ACCEPT || true
iptables -I FORWARD 1 -o flannel.1 -j ACCEPT || true
iptables -I FORWARD 1 -i tailscale0 -j ACCEPT || true
iptables -I FORWARD 1 -o tailscale0 -j ACCEPT || true

# Insert input rules at the top of the INPUT chain
iptables -I INPUT 1 -i flannel.1 -j ACCEPT || true
iptables -I INPUT 1 -i tailscale0 -j ACCEPT || true

# Ensure global forwarding chain is permissive
iptables -P FORWARD ACCEPT || true

log_success "Raw iptables forward & input rules injected successfully."

# Persist iptables rules on Arch Linux if iptables systemd service is utilized
if systemctl is-enabled iptables >/dev/null 2>&1; then
    log_info "iptables systemd service is enabled. Saving rules to /etc/iptables/iptables.rules..."
    iptables-save > /etc/iptables/iptables.rules
    log_success "Rules persisted in /etc/iptables/iptables.rules"
fi

# 5. Output Verification Actions
echo -e "\n=============================================================================="
log_success "Network configuration successfully updated!"
log_info "Next Steps to ensure persistence:"
echo -e "  1. To make the MTU fix permanent, add the following to your K3s server config"
echo -e "     in ${YELLOW}/etc/rancher/k3s/config.yaml${NC} on the master node:"
echo -e "     ${GREEN}flannel-conf: '{\"Network\":\"10.42.0.0/16\",\"Backend\":{\"Type\":\"vxlan\",\"Port\":8472,\"MTU\":1230}}'${NC}"
echo -e "  2. Restart K3s on both nodes to ensure the config file takes effect:"
echo -e "     Master: ${YELLOW}sudo systemctl restart k3s${NC}"
echo -e "     Agent:  ${YELLOW}sudo systemctl restart k3s-agent${NC}"
echo -e "=============================================================================="
