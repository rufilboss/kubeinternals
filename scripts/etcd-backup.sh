#!/bin/bash
set -euo pipefail

# etcd Backup Script
# This script creates a backup of the etcd database
# Run this on the control plane node

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

BACKUP_DIR=${1:-/var/backups/etcd}
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/etcd-backup-$TIMESTAMP.db"

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=========================================="
echo "etcd Backup Script"
echo "=========================================="

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Get etcd pod name
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')

if [ -z "$ETCD_POD" ]; then
    print_error "etcd pod not found"
    exit 1
fi

print_status "Found etcd pod: $ETCD_POD"

# Create backup using etcdctl
print_status "Creating etcd backup..."
kubectl exec -n kube-system $ETCD_POD -- \
    sh -c "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    snapshot save /backup/etcd-snapshot.db"

# Copy backup from pod to host
print_status "Copying backup from pod to host..."
kubectl cp kube-system/$ETCD_POD:/backup/etcd-snapshot.db "$BACKUP_FILE"

# Verify backup
if [ -f "$BACKUP_FILE" ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    print_status "Backup created successfully: $BACKUP_FILE ($BACKUP_SIZE)"
    
    # Get etcd status
    print_status "Current etcd status:"
    kubectl exec -n kube-system $ETCD_POD -- \
        sh -c "ETCDCTL_API=3 etcdctl \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/server.crt \
        --key=/etc/kubernetes/pki/etcd/server.key \
        endpoint status" | head -1
    
    echo ""
    echo "=========================================="
    echo -e "${GREEN}Backup Complete!${NC}"
    echo "=========================================="
    echo "Backup location: $BACKUP_FILE"
    echo ""
    echo "To restore this backup, run:"
    echo "  ./scripts/etcd-restore.sh $BACKUP_FILE"
    echo ""
else
    print_error "Backup file not found"
    exit 1
fi

# Cleanup old backups (keep last 7 days)
print_status "Cleaning up old backups (keeping last 7 days)..."
find "$BACKUP_DIR" -name "etcd-backup-*.db" -mtime +7 -delete
