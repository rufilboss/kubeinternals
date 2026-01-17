# etcd Operations Guide

Comprehensive guide for etcd backup, restore, and maintenance operations in Kubernetes.

## Table of Contents

- [etcd Overview](#etcd-overview)
- [Backup Procedures](#backup-procedures)
- [Restore Procedures](#restore-procedures)
- [Maintenance Operations](#maintenance-operations)
- [Monitoring and Health Checks](#monitoring-and-health-checks)
- [Troubleshooting](#troubleshooting)

## etcd Overview

### What is etcd?

etcd is a distributed, reliable key-value store used by Kubernetes to store all cluster data. It is the single source of truth for the cluster state.

### Key Concepts

- **Quorum**: Majority of etcd members must be available (3-node cluster needs 2 nodes)
- **Raft Consensus**: etcd uses Raft algorithm for consensus
- **Snapshot**: Point-in-time backup of etcd data
- **Defragmentation**: Reclaiming disk space from deleted keys

### Data Stored in etcd

- All Kubernetes objects (pods, services, deployments, etc.)
- Cluster configuration
- Secrets and ConfigMaps
- Service endpoints
- Node information

## Backup Procedures

### Automated Backup Script

Use the provided backup script:

```bash
sudo ./scripts/etcd-backup.sh [backup-directory]
```

**Default backup location**: `/var/backups/etcd/`

**Backup naming**: `etcd-backup-YYYYMMDD-HHMMSS.db`

### Manual Backup

#### Step 1: Identify etcd Pod

```bash
kubectl get pods -n kube-system -l component=etcd
```

#### Step 2: Create Snapshot

```bash
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n kube-system $ETCD_POD -- \
  sh -c "ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /backup/etcd-snapshot.db"
```

#### Step 3: Copy Snapshot to Host

```bash
BACKUP_FILE="/var/backups/etcd/etcd-backup-$(date +%Y%m%d-%H%M%S).db"
kubectl cp kube-system/$ETCD_POD:/backup/etcd-snapshot.db "$BACKUP_FILE"
```

#### Step 4: Verify Backup

```bash
# Check backup file exists and size
ls -lh "$BACKUP_FILE"

# Verify backup integrity
ETCDCTL_API=3 etcdctl snapshot status "$BACKUP_FILE"
```

### Backup Verification

```bash
# Check backup file
ls -lh /var/backups/etcd/

# Verify backup integrity
ETCDCTL_API=3 etcdctl snapshot status /var/backups/etcd/etcd-backup-<timestamp>.db
```

**Expected output**:

```sh
Hash: <hash>
Revision: <revision>
Total Keys: <count>
Total Size: <size>
```

### Backup Schedule

**Recommended**: Every 5 minutes for production

**Cron job example**:

```bash
# Add to crontab
*/5 * * * * /path/to/scripts/etcd-backup.sh
```

**Retention policy**: Keep last 7 days of backups

## Restore Procedures

### Prerequisites

- Valid etcd backup file
- Root access to control plane node
- Cluster downtime expected (15-30 minutes)

### Automated Restore Script

```bash
sudo ./scripts/etcd-restore.sh <backup-file>
```

### Manual Restore

#### Step 1: Stop API Server

```bash
# On control plane node
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml \
       /etc/kubernetes/manifests/kube-apiserver.yaml.backup
```

Wait for API server pod to stop (check with `kubectl get pods -n kube-system`).

#### Step 2: Stop etcd

```bash
sudo mv /etc/kubernetes/manifests/etcd.yaml \
       /etc/kubernetes/manifests/etcd.yaml.backup
```

Wait for etcd pod to stop.

#### Step 3: Backup Current etcd Data

```bash
ETCD_DATA_DIR="/var/lib/etcd"
BACKUP_DATA_DIR="/var/lib/etcd-backup-$(date +%Y%m%d-%H%M%S)"

if [ -d "$ETCD_DATA_DIR" ]; then
    sudo mv "$ETCD_DATA_DIR" "$BACKUP_DATA_DIR"
fi
```

#### Step 4: Restore from Snapshot

```bash
BACKUP_FILE="/var/backups/etcd/etcd-backup-<timestamp>.db"
RESTORE_DIR="/tmp/etcd-restore"
CONTROL_PLANE_IP=$(hostname -I | awk '{print $1}')

# Create restore directory
mkdir -p "$RESTORE_DIR"

# Restore snapshot
ETCDCTL_API=3 etcdctl snapshot restore "$BACKUP_FILE" \
  --data-dir="$RESTORE_DIR" \
  --name=etcd-$(hostname) \
  --initial-cluster=etcd-$(hostname)=https://$CONTROL_PLANE_IP:2380 \
  --initial-cluster-token=etcd-cluster-1 \
  --initial-advertise-peer-urls=https://$CONTROL_PLANE_IP:2380

# Move restored data to etcd directory
sudo mkdir -p /var/lib/etcd
sudo cp -r "$RESTORE_DIR"/* /var/lib/etcd/
sudo chown -R root:root /var/lib/etcd
```

#### Step 5: Restart etcd

```bash
sudo mv /etc/kubernetes/manifests/etcd.yaml.backup \
       /etc/kubernetes/manifests/etcd.yaml
```

Wait for etcd to start (check with `kubectl get pods -n kube-system`).

#### Step 6: Verify etcd Health

```bash
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n kube-system $ETCD_POD -- \
  sh -c "ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health"
```

#### Step 7: Restart API Server

```bash
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml.backup \
       /etc/kubernetes/manifests/kube-apiserver.yaml
```

Wait for API server to start.

#### Step 8: Verify Cluster

```bash
# Check nodes
kubectl get nodes

# Check pods
kubectl get pods -A

# Check cluster info
kubectl cluster-info
```

### Restore Verification Checklist

- [ ] etcd pod is running
- [ ] etcd health check passes
- [ ] API server is running
- [ ] All nodes are Ready
- [ ] System pods are running
- [ ] Application pods are running
- [ ] Services are accessible

## Maintenance Operations

### Health Check

```bash
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')

# Health check
kubectl exec -n kube-system $ETCD_POD -- \
  sh -c "ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health"

# Status check
kubectl exec -n kube-system $ETCD_POD -- \
  sh -c "ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status"
```

### Defragmentation

**When to defragment**: When etcd database size is large but actual data is small

**Warning**: Causes brief unavailability during defragmentation

```bash
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')

# Defragment etcd
kubectl exec -n kube-system $ETCD_POD -- \
  sh -c "ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  defrag"
```

### Compaction

**Purpose**: Remove old history to free space

```bash
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')

# Get current revision
REV=$(kubectl exec -n kube-system $ETCD_POD -- \
  sh -c "ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status" | grep -oP 'revision:[0-9]+' | cut -d: -f2)

# Compact to current revision minus 1000
COMPACT_REV=$((REV - 1000))

kubectl exec -n kube-system $ETCD_POD -- \
  sh -c "ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  compact $COMPACT_REV"
```

### Member List

```bash
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n kube-system $ETCD_POD -- \
  sh -c "ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list"
```

## Monitoring and Health Checks

### Key Metrics to Monitor

1. **etcd Health**: Regular health checks
2. **Database Size**: Monitor growth
3. **Request Latency**: Should be < 100ms
4. **Leader Elections**: Should be minimal
5. **Disk I/O**: Monitor disk performance

### Health Check Script

```bash
#!/bin/bash
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')

if kubectl exec -n kube-system $ETCD_POD -- \
  sh -c "ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health" &> /dev/null; then
    echo "etcd is healthy"
    exit 0
else
    echo "etcd is unhealthy"
    exit 1
fi
```

### Monitoring Queries

```bash
# Get etcd metrics
kubectl get --raw /metrics | grep etcd

# Check etcd pod resource usage
kubectl top pod -n kube-system -l component=etcd
```

## Troubleshooting

### etcd Pod Not Starting

**Symptoms**: etcd pod in `CrashLoopBackOff` or `Pending`

**Debugging**:

```bash
# Check etcd pod logs
kubectl logs -n kube-system -l component=etcd

# Check etcd pod events
kubectl describe pod -n kube-system -l component=etcd

# Check etcd data directory permissions
ls -la /var/lib/etcd

# Check disk space
df -h /var/lib/etcd
```

**Common fixes**:

- Fix data directory permissions
- Free up disk space
- Check certificate validity
- Verify network connectivity

### etcd High Latency

**Symptoms**: Slow API responses, high etcd latency

**Debugging**:
```bash
# Check etcd latency
kubectl exec -n kube-system $ETCD_POD -- \
  sh -c "ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  --write-out=table endpoint status"
```

**Fixes**:
- Defragment etcd
- Check disk I/O performance
- Increase etcd resources
- Consider etcd cluster expansion

### etcd Quorum Loss

**Symptoms**: etcd unavailable, cluster unresponsive

**In single-node setup**: Restore from backup

**In multi-node setup**: 
- Ensure majority of nodes are available
- Remove failed nodes from cluster
- Add new nodes to restore quorum

### Backup Verification Failed

**Symptoms**: Backup file exists but restore fails

**Debugging**:
```bash
# Check backup file integrity
ETCDCTL_API=3 etcdctl snapshot status <backup-file>

# Verify backup file size
ls -lh <backup-file>

# Check backup file permissions
ls -la <backup-file>
```

**Fixes**:
- Use a different backup file
- Verify backup was created correctly
- Check disk space for restore

## Best Practices

1. **Regular Backups**: Automate backups every 5 minutes
2. **Test Restores**: Monthly restore tests
3. **Monitor Health**: Set up alerts for etcd health
4. **Resource Limits**: Set appropriate CPU/memory limits
5. **Disk Performance**: Use SSD for etcd data directory
6. **Network**: Ensure low latency between etcd nodes
7. **Security**: Protect etcd certificates
8. **Documentation**: Document all etcd operations

## Additional Resources

- [etcd Official Documentation](https://etcd.io/docs/)
- [Kubernetes etcd Documentation](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)
- [Recovery Procedures](recovery-procedures.md)
- [Architecture Documentation](architecture.md)

