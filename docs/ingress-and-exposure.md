# Ingress, Routing & Zero-Trust Exposure Runbook

## 1. Overview & Paradigm Shift

In Phase 2 of our cluster architecture, all legacy **NodePort services (30080, 30770, 30779) have been permanently decommissioned**. 

All microservices and administrative consoles now utilize Kubernetes **ClusterIP** services paired with an **Ingress Controller** ([Traefik](https://doc.traefik.io/traefik/providers/kubernetes-ingress/) or [Cloudflare Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)).

```mermaid
graph TD
    subgraph ExposureModels ["Traffic Ingress Models"]
        direction TB
        
        subgraph LocalIngress ["Model A: Local / Tailscale Mesh Ingress (Traefik)"]
            CLIENT_LOCAL["Homelab / Tailscale Client"] -->|HTTP/HTTPS :80/:443| TRAEFIK["K3s Traefik Ingress Controller"]
            TRAEFIK -->|Host: tickets.homelab.local| FRONTEND["ticket-frontend (ClusterIP:80)"]
            TRAEFIK -->|Host: portainer.homelab.local| PORTAINER["portainer (ClusterIP:9000)"]
        end

        subgraph CloudflareIngress ["Model B: Global Zero-Trust Ingress (Cloudflare Tunnel)"]
            CLIENT_REMOTE["Public Internet Client"] -->|HTTPS (DDoS Protected)| CF_EDGE["Cloudflare Edge Anycast"]
            CF_EDGE <==>|Encrypted Outbound Tunnel| CLOUDFLARED["cloudflared Pod (Deployment)"]
            CLOUDFLARED --> FRONTEND
        end
    end
```

---

## 2. Local DNS Resolution Setup

To access services locally using their domain names (`*.homelab.local`), configure local name resolution via one of the following methods:

### Method A: Client `/etc/hosts` (Quickest for development)
Append the Master/Worker node's Tailscale or local LAN IP address to `/etc/hosts` on your client machine:

```bash
# Example /etc/hosts entry
100.x.y.z   tickets.homelab.local
100.x.y.z   portainer.homelab.local
```

### Method B: Homelab DNS (Pi-hole / AdGuard Home / pfSense / OPNsense)
Create a wildcard local DNS record:
* **Domain:** `*.homelab.local`
* **Target IP:** `<Laptop-Master-Tailscale-IP>` or `<LAN-IP>`

---

## 3. Automated TLS with cert-manager

The cluster architecture supports two TLS modes configured via `manifests/base/networking/cert-manager-issuer.yaml`:

1. **Local Self-Signed CA (`homelab-ca-issuer`):**
   Automatically generates valid TLS certificates for `*.homelab.local` without external dependencies.
2. **Let's Encrypt Production (`letsencrypt-production`):**
   Utilizes ACME DNS-01 verification via Cloudflare API to generate valid public Let's Encrypt certificates for custom root domains (e.g. `tickets.yourdomain.com`).

---

## 4. Cloudflare Zero-Trust Tunnel Setup

Cloudflare Tunnels eliminate the need to open firewall ports or expose your home IP address.

### Step-by-Step Deployment:
1. Create a Cloudflare Tunnel in the **Zero Trust Dashboard** under `Networks -> Tunnels`.
2. Copy the generated Tunnel Token.
3. Apply the secret to your cluster:
   ```bash
   kubectl create namespace networking --dry-run=client -o yaml | kubectl apply -f -
   kubectl create secret generic cloudflare-tunnel-credentials \
     -n networking \
     --from-literal=TUNNEL_TOKEN="<YOUR_CLOUDFLARE_TUNNEL_TOKEN>"
   ```
4. Deploy the `cloudflared` daemon:
   ```bash
   kubectl apply -f manifests/base/networking/cloudflare-tunnel.yaml
   ```

---

## 5. Verifying Zero-Trust NetworkPolicies

To verify that PostgreSQL (`ticket-db:5432`) is isolated and only accepts traffic from `ticket-backend`:

### 1. Test Authorized Connection (Backend -> Database):
```bash
kubectl exec -n ticket-system deploy/ticket-backend -- python -c "
import urllib.request, json
res = urllib.request.urlopen('http://localhost:5000/api/health')
print(res.read().decode())
"
# Expected output: {"database":"connected","service":"ticket-backend","status":"healthy"}
```

### 2. Test Blocked Connection (Unauthorized Pod -> Database):
Launch an ephemeral debug container in another namespace and attempt to reach the database port:
```bash
kubectl run network-test --rm -it --image=busybox --restart=Never -n default -- nc -zv -w 3 ticket-db.ticket-system.svc.cluster.local 5432
# Expected output: Connection timed out (Blocked by NetworkPolicy allow-backend-to-db)
```

