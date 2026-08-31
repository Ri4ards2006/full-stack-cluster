# Distributed Storage (Longhorn) & High-Availability Database (CloudNativePG)

## 1. Architectural Paradigm: Decoupling Compute from Physical Disks

In Phase 4, we permanently resolved the **local-path storage constraint** and eliminated hardware node-pinning (`nodeAffinity: richard-desktopp`).

```mermaid
graph TB
    subgraph DataTier ["High-Availability Data Tier (CloudNativePG)"]
        PRIMARY["ticket-db-1 (Primary / RW)<br/>Node: richard-desktopp"]
        STANDBY["ticket-db-2 (Standby / RO)<br/>Node: ThinkPad L480 Master"]
        
        PRIMARY ==="Streaming Replication (WAL)"===> STANDBY
    end

    subgraph LonghornStorageMesh ["Longhorn CSI Distributed Storage Engine"]
        LH_VOL["Longhorn Distributed Block Volume<br/>(pvc-ticket-db / 5Gi, ext4)"]
        
        REP_1["Replica #1 (Synchronous Disk Mirror)<br/>Host Path: /var/lib/longhorn on Desktop"]
        REP_2["Replica #2 (Synchronous Disk Mirror)<br/>Host Path: /var/lib/longhorn on Laptop"]
        
        LH_VOL --- REP_1
        LH_VOL --- REP_2
    end

    subgraph NetworkMesh ["WireGuard Overlay Mesh (Tailscale)"]
        TS_TUNNEL["tailscale0 Encrypted WireGuard Mesh (MTU 1280 / Tuned Flannel MTU 1230)"]
    end

    PRIMARY --> LH_VOL
    STANDBY --> LH_VOL
    REP_1 <===>|Real-Time Block Sync over Mesh| TS_TUNNEL <===>|Real-Time Block Sync over Mesh| REP_2
```

---

## 2. Longhorn Distributed Block Storage Mechanics

### How Block Synchronisation Operates over Tailscale Mesh:
1. **CSI Driver Layer:** Longhorn presents standard Kubernetes `ReadWriteOnce` PersistentVolumes using the `longhorn` StorageClass.
2. **Synchronous Data Mirroring:** For every write operation issued by PostgreSQL:
   * The local Longhorn Engine splits the write into block chunks.
   * Chunk $A$ is committed to the local NVMe drive on `richard-desktopp`.
   * Chunk $B$ is transmitted simultaneously across the `tailscale0` WireGuard mesh to the replica directory `/var/lib/longhorn` on the ThinkPad Master.
   * The write returns `SUCCESS` to PostgreSQL only after both physical nodes acknowledge block persistence.
3. **Volume Auto-Reattachment:** If `richard-desktopp` fails or is rebooted, the Kubernetes scheduler moves the database pod to the Master laptop. Longhorn immediately re-attaches the volume using the local replica without manual intervention.

---

## 3. CloudNativePG PostgreSQL Clustering & Failover

Instead of a single raw PostgreSQL pod, CloudNativePG (CNPG) manages an enterprise-grade, quorum-based database cluster:

### Key Capabilities:
* **Two Distributed Instances (`instances: 2`):** Instance 1 runs on the Desktop; Instance 2 runs on the Laptop.
* **Streaming Replication:** Changes are streamed via PostgreSQL Write-Ahead Logs (WAL).
* **Automated Leader Election & Zero-Downtime Failover:**
  * If the primary database node crashes, CNPG detects the loss of heartbeat within 5 seconds.
  * The standby instance is promoted to primary immediately.
  * The Kubernetes Service `ticket-db-rw` seamlessly routes backend API traffic to the newly promoted primary without requiring any application configuration changes.

---

## 4. Verification & Health Commands

### 1. Check CloudNativePG Cluster Status:
```bash
kubectl get cluster -n ticket-system ticket-db
# Output:
# NAME        INSTANCES   READY   STATUS    PRIMARY
# ticket-db   2           2       Cluster in healthy state   ticket-db-1
```

### 2. Inspect Longhorn Replicas:
```bash
kubectl get volumes.longhorn.io -n longhorn-system
```

### 3. Verify Database Pod Placement & Anti-Affinity:
```bash
kubectl get pods -n ticket-system -o wide -l cnpg.io/cluster=ticket-db
# Verifies ticket-db-1 and ticket-db-2 are running on distinct physical nodes.
```

