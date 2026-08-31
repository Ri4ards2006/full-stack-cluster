# GitOps Operations & ArgoCD Runbook

## 1. Architecture Overview: The "App of Apps" Pattern

In Phase 3, the entire cluster lifecycle is transitioned to a fully declarative **GitOps Continuous Delivery workflow** driven by [ArgoCD](https://argo-cd.readthedocs.io/).

```mermaid
graph TD
    subgraph GitRepository ["Git Source of Truth (GitHub)"]
        ROOT_GIT["manifests/gitops/root-app.yaml"]
        APPS_DIR["manifests/gitops/apps/"]
        OVERLAYS["manifests/overlays/homelab/"]
        BASE_NET["manifests/base/networking/"]
        BASE_PORT["manifests/base/portainer/"]
    end

    subgraph ArgoCDController ["ArgoCD Engine (Namespace: argocd)"]
        ROOT_APP["root-app (Root Controller)"]
        APP_TS["ticket-system App"]
        APP_PORT["portainer App"]
        APP_NET["networking-and-ingress App"]
    end

    subgraph K3sClusterState ["K3s Cluster Namespaces"]
        NS_TS["Namespace: ticket-system<br/>(Backend, Frontend, PostgreSQL)"]
        NS_PORT["Namespace: portainer<br/>(Portainer CE Pod & RBAC)"]
        NS_NET["Namespace: kube-system / default<br/>(Ingress, TLS, NetworkPolicies)"]
    end

    ROOT_GIT -.->|Git Pull / Webhook| ROOT_APP
    ROOT_APP ==>|Discovers Child Apps| APP_TS & APP_PORT & APP_NET
    
    APP_TS -->|Reconciles & Self-Heals| NS_TS
    APP_PORT -->|Reconciles & Self-Heals| NS_PORT
    APP_NET -->|Reconciles & Self-Heals| NS_NET
```

---

## 2. Bootstrapping ArgoCD on K3s

### Step 1: Install ArgoCD Base Stack
Apply the declarative ArgoCD base installation:
```bash
kubectl apply -k manifests/base/argocd/
```

Verify that all controller and server pods are running:
```bash
kubectl get pods -n argocd -w
```

### Step 2: Retrieve the Initial Admin Password
Extract and decode the default admin credentials:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

### Step 3: Access the Web UI
Ensure `argocd.homelab.local` points to your Laptop/Desktop node in `/etc/hosts`:
```bash
# Example /etc/hosts entry
100.x.y.z   argocd.homelab.local
```
Navigate to **`https://argocd.homelab.local`** and log in with username `admin` and the retrieved password.

---

## 3. Deploying the Root Application

To initialize automated discovery and synchronization for all cluster workloads, apply the root application manifest:

```bash
kubectl apply -f manifests/gitops/root-app.yaml
```

Once applied:
1. `root-app` reads all child applications defined in `manifests/gitops/apps/`.
2. ArgoCD provisions `ticket-system`, `portainer`, and `networking-and-ingress`.
3. Automatic **Self-Healing** (`automated.selfHeal=true`) and **Pruning** (`automated.prune=true`) ensure that any manual out-of-band edits (`kubectl edit`, accidental deletions) are immediately reverted back to the Git state.

---

## 4. End-to-End GitOps Development Lifecycle

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Developer
    participant Git as GitHub (full-stack-cluster)
    participant CI as GitHub Actions
    participant Registry as GitHub Container Registry (ghcr.io)
    participant ArgoCD as ArgoCD Controller (K3s)
    participant Cluster as K3s Workloads

    Dev->>Git: Push feature branch / Pull Request
    Git->>CI: Trigger ci.yaml
    CI->>Registry: Build & Push Multi-Arch OCI Image (tag: sha-xxxx)
    Dev->>Git: Merge PR to 'main'
    Git->>ArgoCD: Webhook notification (or 3-min poll cycle)
    ArgoCD->>Git: Fetch latest commits & Kustomize manifests
    ArgoCD->>Cluster: Apply diffs, roll out zero-downtime rolling updates
    Cluster-->>ArgoCD: Return Healthy & Synced status
```

---

## 5. Disaster Recovery & Cluster Rebuilding

In the event of total hardware loss or cluster re-installation:
1. Re-install K3s on bare-metal using `config/k3s/config.yaml.example`.
2. Re-apply secrets:
   ```bash
   kubectl apply -f manifests/secrets.yaml
   ```
3. Install ArgoCD:
   ```bash
   kubectl apply -k manifests/base/argocd/
   ```
4. Restore all services in a single command:
   ```bash
   kubectl apply -f manifests/gitops/root-app.yaml
   ```
The entire microservice suite, ingress rules, network policies, and administrative tools will self-assemble within 60 seconds.

