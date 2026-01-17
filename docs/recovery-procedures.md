# Cluster Recovery Procedures

> **"If the control plane goes down, the company stops making money."**

This document provides step-by-step procedures for recovering from various cluster failure scenarios. Each procedure has been tested and documented to ensure rapid recovery.

## Table of Contents

- [Recovery Philosophy](#recovery-philosophy)
- [Pre-Recovery Checklist](#pre-recovery-checklist)
- [Scenario 1: Pod Eviction Recovery](#scenario-1-pod-eviction-recovery)
- [Scenario 2: Node Failure Recovery](#scenario-2-node-failure-recovery)
- [Scenario 3: Control Plane Failure](#scenario-3-control-plane-failure)
- [Scenario 4: etcd Failure and Restore](#scenario-4-etcd-failure-and-restore)
- [Scenario 5: CrashLoopBackOff Recovery](#scenario-5-crashloopbackoff-recovery)
- [Scenario 6: Network Partition Recovery](#scenario-6-network-partition-recovery)
- [Post-Recovery Verification](#post-recovery-verification)
- [Lessons Learned Template](#lessons-learned-template)

## Recovery Philosophy

### RTO and RPO

- **Recovery Time Objective (RTO)**: < 15 minutes for control plane
- **Recovery Point Objective (RPO)**: < 5 minutes (etcd backup frequency)

### Recovery Principles

1. **Assess First**: Understand the scope before acting
2. **Isolate Impact**: Prevent cascading failures
3. **Document Everything**: Record actions for post-mortem
4. **Verify Continuously**: Check status after each step
5. **Communicate**: Keep stakeholders informed

## Pre-Recovery Checklist

Before starting any recovery procedure:

- [ ] Identify the failure type and scope
- [ ] Check if etcd backup exists and is recent
- [ ] Verify network connectivity
- [ ] Document current cluster state
- [ ] Notify stakeholders if production impact
- [ ] Have recovery scripts ready
- [ ] Ensure access to control plane node

### Quick Status Check

```bash
# Check cluster nodes
kubectl get nodes

# Check all pods
kubectl get pods -A

# Check events
kubectl get events --sort-by='.lastTimestamp' | tail -20

# Check control plane components
kubectl get pods -n kube-system

# Check resource usage
kubectl top nodes
kubectl top pods -A
```

## Scenario 1: Pod Eviction Recovery

### Symptoms

- Pods in `Evicted` state
- Events showing `Insufficient memory` or `Insufficient cpu`
- Node pressure conditions

### Diagnosis

```bash
# Check evicted pods
kubectl get pods -A | grep Evicted

# Check node conditions
kubectl describe node <node-name> | grep -A 5 Conditions

# Check events
kubectl get events --field-selector reason=FailedScheduling
```

### Recovery Steps

1. **Identify Root Cause**

   ```bash
   # Check node resource usage
   kubectl top node <node-name>
   
   # Check pod resource requests
   kubectl describe node <node-name> | grep -A 10 "Allocated resources"
   ```

2. **Free Up Resources**

   ```bash
   # Delete evicted pods
   kubectl get pods -A -o json | \
     jq '.items[] | select(.status.reason=="Evicted") | .metadata | "\(.namespace) \(.name)"' | \
     xargs -n2 kubectl delete pod -n
   
   # Or manually delete
   kubectl delete pod <evicted-pod-name> -n <namespace>
   ```

3. **Scale Down Non-Critical Workloads**

   ```bash
   kubectl scale deployment <non-critical-deployment> --replicas=0
   ```

4. **Add Node or Increase Resources**

   ```bash
   # If using cloud provider, add node
   # Or increase node resources
   ```

5. **Verify Recovery**

   ```bash
   kubectl get pods -A
   kubectl get nodes
   ```

### Prevention

- Set appropriate resource requests and limits
- Implement resource quotas
- Monitor node capacity
- Use HPA for automatic scaling

## Scenario 2: Node Failure Recovery

### Symptoms

- Node status: `NotReady`
- Pods on node: `Unknown` or `NodeLost`
- No heartbeat from kubelet

### Diagnosis

```bash
# Check node status
kubectl get nodes

# Check pods on failed node
kubectl get pods -A -o wide | grep <node-name>

# Check node conditions
kubectl describe node <node-name>
```

### Recovery Steps

#### Option A: Node Recoverable (Temporary Issue)

1. **Check Node Connectivity**

   ```bash
   ssh <node-ip>
   systemctl status kubelet
   ```

2. **Restart Kubelet**

   ```bash
   sudo systemctl restart kubelet
   sudo systemctl status kubelet
   ```

3. **Verify Node Recovery**

   ```bash
   kubectl get nodes
   # Wait for node to become Ready
   ```

#### Option B: Node Unrecoverable (Permanent Failure)

1. **Cordon Node** (if still accessible)

   ```bash
   kubectl cordon <node-name>
   ```

2. **Drain Node** (evict pods gracefully)

   ```bash
   kubectl drain <node-name> \
     --ignore-daemonsets \
     --delete-emptydir-data \
     --force \
     --grace-period=300
   ```

3. **Delete Node from Cluster**

   ```bash
   kubectl delete node <node-name>
   ```

4. **Replace Node**

   ```bash
   # On new node, join to cluster
   sudo ./scripts/join-worker-node.sh <token> <hash> <control-plane-ip>
   ```

5. **Verify Pods Rescheduled**

   ```bash
   kubectl get pods -A -o wide
   # Ensure all pods are running on healthy nodes
   ```

### Prevention

- Use multiple worker nodes (minimum 2)
- Implement pod disruption budgets
- Use anti-affinity rules for critical pods
- Monitor node health proactively

## Scenario 3: Control Plane Failure

### Symptoms

- `kubectl` commands timeout
- API server unreachable
- No response from control plane

### Diagnosis

```bash
# Test API server connectivity
kubectl cluster-info

# Check control plane node
ssh <control-plane-ip>
systemctl status kubelet
systemctl status containerd
```

### Recovery Steps

1. **Access Control Plane Node**

   ```bash
   ssh <control-plane-ip>
   ```

2. **Check Component Status**

   ```bash
   # Check static pods
   ls -la /etc/kubernetes/manifests/
   
   # Check kubelet
   sudo systemctl status kubelet
   sudo journalctl -u kubelet -n 50
   ```

3. **Restart Failed Components**

   **API Server:**

   ```bash
   # Check if manifest exists
   ls /etc/kubernetes/manifests/kube-apiserver.yaml
   
   # If missing, restore from backup
   sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml.backup \
          /etc/kubernetes/manifests/kube-apiserver.yaml
   
   # Restart kubelet to recreate pod
   sudo systemctl restart kubelet
   ```

   **Controller Manager:**

   ```bash
   sudo systemctl restart kubelet
   ```

   **Scheduler:**

   ```bash
   sudo systemctl restart kubelet
   ```

4. **Verify API Server**

   ```bash
   # Wait 30-60 seconds
   kubectl get nodes
   kubectl get pods -n kube-system
   ```

5. **Check Cluster Health**

   ```bash
   kubectl get componentstatuses
   kubectl get nodes
   kubectl get pods -A
   ```

### Prevention

- Use HA control plane (3+ nodes)
- Regular health checks
- Automated monitoring and alerts
- Load balancer for API server

## Scenario 4: etcd Failure and Restore

### Symptoms

- etcd pod not running
- API server cannot connect to etcd
- Cluster state inconsistent or lost

### Diagnosis

```bash
# Check etcd pod
kubectl get pods -n kube-system -l component=etcd

# Check etcd logs
kubectl logs -n kube-system <etcd-pod-name>

# Test etcd connectivity
kubectl exec -n kube-system <etcd-pod-name> -- \
  etcdctl endpoint health
```

### Recovery Steps

#### Option A: etcd Pod Restart (No Data Loss)

1. **Check etcd Status**

   ```bash
   kubectl get pods -n kube-system -l component=etcd
   ```

2. **Restart etcd**

   ```bash
   # On control plane node
   sudo systemctl restart kubelet
   
   # Or manually restart static pod
   sudo mv /etc/kubernetes/manifests/etcd.yaml \
          /etc/kubernetes/manifests/etcd.yaml.backup
   sleep 5
   sudo mv /etc/kubernetes/manifests/etcd.yaml.backup \
          /etc/kubernetes/manifests/etcd.yaml
   ```

3. **Verify etcd Health**

   ```bash
   kubectl exec -n kube-system <etcd-pod-name> -- \
     sh -c "ETCDCTL_API=3 etcdctl \
     --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key \
     endpoint health"
   ```

#### Option B: etcd Restore from Backup (Data Loss)

1. **Stop API Server**

   ```bash
   # On control plane node
   sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml \
          /etc/kubernetes/manifests/kube-apiserver.yaml.backup
   ```

2. **Stop etcd**

   ```bash
   sudo mv /etc/kubernetes/manifests/etcd.yaml \
          /etc/kubernetes/manifests/etcd.yaml.backup
   ```

3. **Restore etcd from Backup**

   ```bash
   # Use restore script
   sudo ./scripts/etcd-restore.sh /var/backups/etcd/etcd-backup-<timestamp>.db
   
   # Or manually:
   # 1. Backup current etcd data
   # 2. Restore from backup file
   # 3. Restart etcd
   ```

4. **Restart API Server**

   ```bash
   sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml.backup \
          /etc/kubernetes/manifests/kube-apiserver.yaml
   ```

5. **Verify Cluster**

   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```

### Prevention

- **Automated Backups**: Every 5 minutes
- **Test Restores**: Monthly restore tests
- **HA etcd**: 3+ etcd nodes in production
- **Monitoring**: Alert on etcd health issues

## Scenario 5: CrashLoopBackOff Recovery

### Symptoms

- Pod status: `CrashLoopBackOff`
- Pod continuously restarting
- Application errors in logs

### Diagnosis

```bash
# Check pod status
kubectl get pods -A | grep CrashLoopBackOff

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check pod logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous  # Previous container instance
```

### Recovery Steps

1. **Identify Root Cause**

   ```bash
   # Get detailed pod information
   kubectl describe pod <pod-name> -n <namespace>
   
   # Check logs
   kubectl logs <pod-name> -n <namespace> --tail=100
   
   # Check previous container logs
   kubectl logs <pod-name> -n <namespace> --previous
   ```

2. **Common Causes and Fixes**

   **Application Error:**

   ```bash
   # Fix application code/config
   # Update deployment
   kubectl set image deployment/<deployment-name> \
     <container-name>=<new-image> -n <namespace>
   ```

   **Configuration Error:**

   ```bash
   # Check ConfigMap/Secret
   kubectl get configmap <configmap-name> -n <namespace> -o yaml
   kubectl get secret <secret-name> -n <namespace> -o yaml
   
   # Fix and apply
   kubectl apply -f <fixed-config>.yaml
   ```

   **Resource Limits:**

   ```bash
   # Check resource usage
   kubectl top pod <pod-name> -n <namespace>
   
   # Increase limits in deployment
   kubectl edit deployment <deployment-name> -n <namespace>
   ```

   **Missing Dependencies:**

   ```bash
   # Check if dependent services are running
   kubectl get svc -n <namespace>
   kubectl get pods -n <namespace>
   ```

3. **Temporary Workaround**

   ```bash
   # Delete pod to force recreation
   kubectl delete pod <pod-name> -n <namespace>
   
   # Or restart deployment
   kubectl rollout restart deployment/<deployment-name> -n <namespace>
   ```

4. **Verify Recovery**

   ```bash
   kubectl get pods -n <namespace>
   kubectl logs <pod-name> -n <namespace> -f
   ```

### Prevention

- Comprehensive testing before deployment
- Proper health checks (liveness/readiness)
- Resource limits based on actual usage
- Dependency checks in startup scripts

## Scenario 6: Network Partition Recovery

### Symptoms

- Nodes unreachable
- Pods cannot communicate
- Service discovery failing

### Diagnosis

```bash
# Check node connectivity
kubectl get nodes
ping <node-ip>

# Check network policies
kubectl get networkpolicies -A

# Check service endpoints
kubectl get endpoints -A
```

### Recovery Steps

1. **Identify Partition Scope**

   ```bash
   # Check which nodes are affected
   kubectl get nodes -o wide
   
   # Test connectivity
   ping <node-ip>
   ssh <node-ip> "hostname"
   ```

2. **Fix Network Issues**

   **Firewall Rules:**

   ```bash
   # Check iptables
   sudo iptables -L -n
   
   # Remove blocking rules
   sudo iptables -D OUTPUT -d <blocked-ip> -j DROP
   ```

   **Network Policies:**

   ```bash
   # Check network policies
   kubectl get networkpolicies -A
   
   # Temporarily remove restrictive policies
   kubectl delete networkpolicy <policy-name> -n <namespace>
   ```

   **CNI Plugin:**

   ```bash
   # Restart CNI pods
   kubectl delete pods -n kube-system -l k8s-app=calico-node
   ```

3. **Verify Connectivity**

   ```bash
   # Test pod-to-pod communication
   kubectl run test-pod --image=busybox --rm -it -- sh
   # Inside pod: ping <other-pod-ip>
   
   # Test service discovery
   nslookup <service-name>.<namespace>.svc.cluster.local
   ```

### Prevention

- Proper firewall configuration
- Network policies with testing
- CNI plugin monitoring
- Regular network connectivity tests

## Post-Recovery Verification

After any recovery procedure, perform these checks:

### 1. Cluster Health

```bash
# All nodes ready
kubectl get nodes

# All system pods running
kubectl get pods -n kube-system

# Component status
kubectl get componentstatuses
```

### 2. Application Health

```bash
# All application pods running
kubectl get pods -A

# Services accessible
kubectl get svc -A

# Test application endpoints
curl http://<service-ip>:<port>/health
```

### 3. Resource Usage

```bash
# Node resources
kubectl top nodes

# Pod resources
kubectl top pods -A
```

### 4. Events

```bash
# Check for errors
kubectl get events --sort-by='.lastTimestamp' | grep -i error
```

## Lessons Learned Template

After each incident, document:

```markdown
## Incident: [Date] - [Failure Type]

### Timeline
- [Time] - Incident detected
- [Time] - Recovery started
- [Time] - Recovery completed

### Root Cause
[Detailed explanation]

### Impact
- Services affected: [List]
- Downtime: [Duration]
- Data loss: [Yes/No, details]

### Recovery Actions
1. [Action 1]
2. [Action 2]
...

### Prevention Measures
- [ ] [Action item 1]
- [ ] [Action item 2]
...

### Improvements
- [ ] [Improvement 1]
- [ ] [Improvement 2]
...
```

## Emergency Contacts

- **On-Call Engineer**: [Contact]
- **Kubernetes Admin**: [Contact]
- **Infrastructure Team**: [Contact]

## Additional Resources

- [etcd Operations Guide](etcd-operations.md)
- [Debugging Guide](debugging-guide.md)
- [Architecture Documentation](architecture.md)
