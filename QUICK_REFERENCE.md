# Quick Reference Guide

Quick commands and procedures for common operations.

## Cluster Setup

```bash
# Control Plane
sudo ./scripts/setup-control-plane.sh

# Worker Node
sudo ./scripts/join-worker-node.sh <token> <hash> <control-plane-ip>
```

## Service Deployment

```bash
# All services
kubectl apply -f manifests/

# Individual services
kubectl apply -f manifests/api-service/
kubectl apply -f manifests/worker-service/
kubectl apply -f manifests/redis/
kubectl apply -f manifests/postgresql/
```

## Common Commands

### Cluster Status

```bash
kubectl get nodes
kubectl get pods -A
kubectl get svc -A
kubectl get events --sort-by='.lastTimestamp'
```

### Pod Operations

```bash
# Get pods
kubectl get pods -n production

# Describe pod
kubectl describe pod <pod-name> -n production

# Logs
kubectl logs <pod-name> -n production
kubectl logs <pod-name> -n production --previous

# Exec into pod
kubectl exec -it <pod-name> -n production -- /bin/sh
```

### Service Operations

```bash
# Get services
kubectl get svc -n production

# Get endpoints
kubectl get endpoints -n production

# Port forward
kubectl port-forward -n production svc/api-service 8080:80
```

## etcd Operations

### Backup

```bash
sudo ./scripts/etcd-backup.sh
```

### Restore

```bash
sudo ./scripts/etcd-restore.sh /var/backups/etcd/etcd-backup-<timestamp>.db
```

### Health Check

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

## Failure Scenarios

### Pod Eviction

```bash
./scripts/simulate-failures.sh pod-eviction
```

### Node Failure

```bash
./scripts/simulate-failures.sh node-failure <node-name>
```

### CrashLoopBackOff

```bash
./scripts/simulate-failures.sh crashloop api-service
```

### Control Plane Failure

```bash
./scripts/simulate-failures.sh api-server-down
```

## Debugging

### Check Pod Status

```bash
kubectl describe pod <pod-name> -n production
kubectl get events --field-selector involvedObject.name=<pod-name> -n production
```

### Check Node Status

```bash
kubectl describe node <node-name>
kubectl top node <node-name>
```

### Check Resource Usage

```bash
kubectl top nodes
kubectl top pods -n production
```

### Network Debugging

```bash
# Test DNS
kubectl run test-dns --image=busybox --rm -it -- \
  nslookup api-service.production.svc.cluster.local

# Test connectivity
kubectl run test-curl --image=curlimages/curl --rm -it -- \
  curl http://api-service.production.svc.cluster.local
```

## Load Testing

```bash
# API Service
./scripts/load-test.sh api-service 1000

# With duration
./scripts/load-test.sh api-service 1000 60
```

## Recovery Procedures

### Pod Eviction

1. Check evicted pods: `kubectl get pods -A | grep Evicted`
2. Delete evicted pods
3. Check node resources: `kubectl top node`
4. Scale if needed

### Node Failure

1. Cordon node: `kubectl cordon <node-name>`
2. Drain node: `kubectl drain <node-name> --ignore-daemonsets`
3. Replace node or fix issue
4. Uncordon: `kubectl uncordon <node-name>`

### etcd Restore

1. Stop API server
2. Stop etcd
3. Restore from backup: `sudo ./scripts/etcd-restore.sh <backup-file>`
4. Restart components
5. Verify cluster

## Useful Aliases

Add to `~/.bashrc`:

```bash
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kdp='kubectl describe pod'
alias kds='kubectl describe svc'
alias kdn='kubectl describe node'
alias kl='kubectl logs'
alias ke='kubectl exec -it'
```

## Documentation Quick Links

- [Architecture](docs/architecture.md)
- [Recovery Procedures](docs/recovery-procedures.md)
- [Debugging Guide](docs/debugging-guide.md)
- [etcd Operations](docs/etcd-operations.md)
- [Deployment Guide](docs/deployment-guide.md)
- [Cluster Internals](docs/cluster-internals.md)
