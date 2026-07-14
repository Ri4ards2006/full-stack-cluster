#!/usr/bin/env bash

# ==============================================================================
# Script: fix-k3s-dns-persistent.sh
# Description: Production-grade static resolv.conf injection and systemd unit
#              modification for K3s Master (Server) and Worker (Agent) nodes.
# Usage: sudo ./fix-k3s-dns-persistent.sh
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

log_info "Initializing K3s persistent DNS remediation..."

# 2. Create Static resolv.conf File
RESOLV_DIR="/etc/rancher/k3s"
RESOLV_FILE="$RESOLV_DIR/resolv.conf"

log_info "Creating static DNS configuration at $RESOLV_FILE..."
mkdir -p "$RESOLV_DIR"

cat << 'EOF' > "$RESOLV_FILE"
# Static upstream nameservers for K3s (bypasses systemd-resolved loops)
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

chmod 644 "$RESOLV_FILE"
log_success "Static resolv.conf created with Google and Cloudflare nameservers."

# 3. Patch Systemd Service Files
# A. Master Node (K3s Server Service)
K3S_SERVER_SERVICE="/etc/systemd/system/k3s.service"
if [[ -f "$K3S_SERVER_SERVICE" ]]; then
    log_info "Detected K3s server service file at $K3S_SERVER_SERVICE"
    if grep -q "resolv-conf" "$K3S_SERVER_SERVICE"; then
        log_warn "resolv-conf parameter already exists in $K3S_SERVER_SERVICE. Skipping modification."
    else
        log_info "Appending --resolv-conf argument to $K3S_SERVER_SERVICE..."
        python3 -c '
import re
with open("/etc/systemd/system/k3s.service", "r") as f:
    content = f.read()

# Match ExecStart block ending with a backslash and a blank line
match = re.search(r"(ExecStart=[\s\S]*?\\)\n\s*\n", content)
if match:
    exec_block = match.group(1)
    new_exec_block = exec_block + "\n\t'\''--resolv-conf=/etc/rancher/k3s/resolv.conf'\''"
    content = content.replace(exec_block, new_exec_block)
    with open("/etc/systemd/system/k3s.service", "w") as f:
        f.write(content)
    print("Parser Success: Appended argument to multi-line ExecStart.")
else:
    # Line-by-line fallback
    lines = content.splitlines()
    for idx, line in enumerate(lines):
        if line.startswith("ExecStart=") and "resolv-conf" not in line:
            if line.endswith("\\"):
                lines[idx] = line + "\n\t'\''--resolv-conf=/etc/rancher/k3s/resolv.conf'\''"
            else:
                lines[idx] = line + " --resolv-conf=/etc/rancher/k3s/resolv.conf"
            content = "\n".join(lines) + "\n"
            with open("/etc/systemd/system/k3s.service", "w") as f:
                f.write(content)
            print("Parser Success: Appended argument using line-by-line fallback.")
            break
'
        log_success "k3s.service successfully updated."
    fi
fi

# B. Worker Node (K3s Agent Service)
K3S_AGENT_SERVICE="/etc/systemd/system/k3s-agent.service"
if [[ -f "$K3S_AGENT_SERVICE" ]]; then
    log_info "Detected K3s agent service file at $K3S_AGENT_SERVICE"
    if grep -q "resolv-conf" "$K3S_AGENT_SERVICE"; then
        log_warn "resolv-conf parameter already exists in $K3S_AGENT_SERVICE. Skipping modification."
    else
        log_info "Appending --resolv-conf argument to $K3S_AGENT_SERVICE..."
        python3 -c '
import re
with open("/etc/systemd/system/k3s-agent.service", "r") as f:
    content = f.read()

match = re.search(r"(ExecStart=[\s\S]*?\\)\n\s*\n", content)
if match:
    exec_block = match.group(1)
    new_exec_block = exec_block + "\n\t'\''--resolv-conf=/etc/rancher/k3s/resolv.conf'\''"
    content = content.replace(exec_block, new_exec_block)
    with open("/etc/systemd/system/k3s-agent.service", "w") as f:
        f.write(content)
    print("Parser Success: Appended argument to multi-line ExecStart.")
else:
    lines = content.splitlines()
    for idx, line in enumerate(lines):
        if line.startswith("ExecStart=") and "resolv-conf" not in line:
            if line.endswith("\\"):
                lines[idx] = line + "\n\t'\''--resolv-conf=/etc/rancher/k3s/resolv.conf'\''"
            else:
                lines[idx] = line + " --resolv-conf=/etc/rancher/k3s/resolv.conf"
            content = "\n".join(lines) + "\n"
            with open("/etc/systemd/system/k3s-agent.service", "w") as f:
                f.write(content)
            print("Parser Success: Appended argument using line-by-line fallback.")
            break
'
        log_success "k3s-agent.service successfully updated."
    fi
fi

# 4. Apply Systemd Configurations & Restart Services
log_info "Reloading systemd daemon..."
systemctl daemon-reload

if systemctl is-active --quiet k3s; then
    log_info "Restarting K3s Server Service..."
    systemctl restart k3s
    log_success "K3s Server Service restarted."
fi

if systemctl is-active --quiet k3s-agent; then
    log_info "Restarting K3s Agent Service..."
    systemctl restart k3s-agent
    log_success "K3s Agent Service restarted."
fi

# 5. Evict Pods to Force DNS Updates (Only if running on Master Node)
K3S_CONFIG="/etc/rancher/k3s/k3s.yaml"
if [[ -f "$K3S_CONFIG" ]] && command -v kubectl >/dev/null; then
    log_info "Kubeconfig detected. Purging active pods to force nameserver inheritance..."
    
    # Evicting all pods across all namespaces
    kubectl --kubeconfig "$K3S_CONFIG" delete pods --all -A
    
    log_success "All pods evicted. CoreDNS and application containers are recreating with the static resolv.conf."
else
    log_warn "Kubeconfig or kubectl command not found on this machine. If this is a worker node, ignore this."
    log_warn "If this is the master node, run: 'sudo kubectl delete pods --all -A' to apply DNS update."
fi

echo -e "\n=============================================================================="
log_success "K3s Persistent DNS configuration complete!"
log_info "You can verify the CoreDNS pods are querying the new nameservers by running:"
echo -e "  ${GREEN}sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml describe pod -n kube-system -l k8s-app=kube-dns${NC}"
echo -e "=============================================================================="
