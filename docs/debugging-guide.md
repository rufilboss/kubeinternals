# Kubernetes Debugging Guide

A comprehensive guide to debugging Kubernetes cluster issues, from common problems to advanced troubleshooting techniques.

## Table of Contents

- [Debugging Methodology](#debugging-methodology)
- [Essential Commands](#essential-commands)
- [Common Issues](#common-issues)
- [Pod Debugging](#pod-debugging)
- [Node Debugging](#node-debugging)
- [Network Debugging](#network-debugging)
- [Control Plane Debugging](#control-plane-debugging)
- [Performance Debugging](#performance-debugging)
- [Debugging Tools](#debugging-tools)

## Debugging Methodology

### The Debugging Process

1. **Observe**: Gather information about the current state
2. **Hypothesize**: Form theories about what might be wrong
3. **Test**: Verify hypotheses with targeted commands
4. **Fix**: Apply the solution
5. **Verify**: Confirm the fix works
6. **Document**: Record the issue and solution

### Information Gathering Checklist

- [ ] Current cluster state (`kubectl get all -A`)
- [ ] Recent events (`kubectl get events`)
- [ ] Pod logs (`kubectl logs`)
- [ ] Node status (`kubectl get nodes -o wide`)
- [ ] Resource usage (`kubectl top`)
- [ ] Network connectivity
- [ ] Configuration files

## Essential Commands

### Cluster Overview

```bash
# Get all resources
kubectl get all -A

# Get nodes with details
kubectl get nodes -o wide

# Get all pods with node assignment
kubectl get pods -A -o wide

# Get services
kubectl get svc -A

# Get events (sorted by time)
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

### Resource Details

```bash
# Describe a pod
kubectl describe pod <pod-name> -n <namespace>

# Describe a node
kubectl describe node <node-name>

# Describe a service
kubectl describe svc <service-name> -n <namespace>

# Get YAML of a resource
kubectl get <resource> <name> -n <namespace> -o yaml
```

### Logs

```bash
# Pod logs
kubectl logs <pod-name> -n <namespace>

# Previous container instance logs
kubectl logs <pod-name> -n <namespace> --previous

# Follow logs
kubectl logs <pod-name> -n <namespace> -f

# Logs from all containers in pod
kubectl logs <pod-name> -n <namespace> --all-containers=true

# Logs with timestamps
kubectl logs <pod-name> -n <namespace> --timestamps
```

## Common Issues

### CrashLoopBackOff

**Symptoms**: Pod continuously restarting, status shows `CrashLoopBackOff`

**Debugging Steps**:

1. **Check pod status**
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   ```

2. **Check logs**
   ```bash
   kubectl logs <pod-name> -n <namespace>
   kubectl logs <pod-name> -n <namespace> --previous
   ```

3. **Check events**
   ```bash
   kubectl get events --field-selector involvedObject.name=<pod-name> -n <namespace>
   ```

4. **Common Causes**:
   - Application error (check logs)
   - Configuration error (ConfigMap/Secret)
   - Resource limits exceeded
   - Missing dependencies
   - Image pull error

**Example Debug Session**:
```bash
# Get pod details
kubectl describe pod api-service-xxx -n production

# Check logs
kubectl logs api-service-xxx -n production

# Check if it's a configuration issue
kubectl get configmap api-config -n production -o yaml

# Check resource limits
kubectl top pod api-service-xxx -n production
```

### Pod Stuck in Pending

**Symptoms**: Pod status is `Pending`, not scheduled to any node

**Debugging Steps**:

1. **Check why pod is pending**
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   # Look for "Events" section
   ```

2. **Common reasons**:
   - Insufficient resources
   - Node selector/affinity not matching
   - Taints not tolerated
   - PVC not bound
   - No nodes available

**Example**:
```bash
# Check events
kubectl describe pod my-pod -n production | grep -A 10 Events

# Check node resources
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check PVC status
kubectl get pvc -n production
```

### ImagePullBackOff

**Symptoms**: Pod cannot start, status shows `ImagePullBackOff`

**Debugging Steps**:

1. **Check image name**
   ```bash
   kubectl describe pod <pod-name> -n <namespace> | grep Image
   ```

2. **Test image pull manually**
   ```bash
   docker pull <image-name>
   # or
   crictl pull <image-name>
   ```

3. **Check image pull secrets**
   ```bash
   kubectl get secrets -n <namespace>
   kubectl describe pod <pod-name> -n <namespace> | grep -i secret
   ```

**Fix**:
```bash
# Update image
kubectl set image deployment/<deployment-name> \
  <container-name>=<correct-image> -n <namespace>

# Or add image pull secret
kubectl patch deployment <deployment-name> -n <namespace> \
  -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"<secret-name>"}]}}}}'
```

### Service Not Accessible

**Symptoms**: Cannot reach service from pods or externally

**Debugging Steps**:

1. **Check service endpoints**
   ```bash
   kubectl get endpoints <service-name> -n <namespace>
   kubectl describe svc <service-name> -n <namespace>
   ```

2. **Check pod labels match service selector**
   ```bash
   kubectl get svc <service-name> -n <namespace> -o yaml | grep selector
   kubectl get pods -n <namespace> --show-labels
   ```

3. **Test DNS resolution**
   ```bash
   kubectl run test-pod --image=busybox --rm -it -- nslookup <service-name>.<namespace>.svc.cluster.local
   ```

4. **Test connectivity**
   ```bash
   kubectl run test-pod --image=busybox --rm -it -- wget -O- http://<service-name>.<namespace>.svc.cluster.local
   ```

**Example**:
```bash
# Check service
kubectl get svc api-service -n production

# Check endpoints
kubectl get endpoints api-service -n production

# Test from pod
kubectl run curl-test --image=curlimages/curl --rm -it -- \
  curl http://api-service.production.svc.cluster.local
```

## Pod Debugging

### Interactive Debugging

```bash
# Execute command in running pod
kubectl exec <pod-name> -n <namespace> -- <command>

# Get shell in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Debug pod with ephemeral container (Kubernetes 1.23+)
kubectl debug <pod-name> -n <namespace> -it --image=busybox
```

### Resource Issues

```bash
# Check resource usage
kubectl top pod <pod-name> -n <namespace>

# Check resource requests/limits
kubectl describe pod <pod-name> -n <namespace> | grep -A 5 "Limits\|Requests"

# Check if pod was evicted
kubectl get events --field-selector reason=Evicted -n <namespace>
```

### Health Check Issues

```bash
# Check probe configuration
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 10 "livenessProbe\|readinessProbe"

# Manually test health endpoint
kubectl exec <pod-name> -n <namespace> -- curl http://localhost:8080/health

# Check probe failures in events
kubectl get events --field-selector reason=Unhealthy -n <namespace>
```

## Node Debugging

### Node Status

```bash
# Get node details
kubectl describe node <node-name>

# Check node conditions
kubectl get node <node-name> -o yaml | grep -A 10 conditions

# Check node resources
kubectl top node <node-name>
```

### Node Issues

**Node NotReady**:
```bash
# Check kubelet status (on node)
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 50

# Check container runtime
sudo systemctl status containerd
# or
sudo systemctl status docker

# Check node conditions
kubectl describe node <node-name> | grep -A 5 Conditions
```

**Resource Pressure**:
```bash
# Check node resources
kubectl describe node <node-name> | grep -A 10 "Allocated resources"

# Check for evicted pods
kubectl get pods -A --field-selector status.phase=Failed

# Check node conditions
kubectl get node <node-name> -o jsonpath='{.status.conditions}'
```

### Node Logs

```bash
# On the node itself
sudo journalctl -u kubelet -f
sudo journalctl -u containerd -f

# Check kubelet logs
sudo tail -f /var/log/kubelet.log
```

## Network Debugging

### Service Discovery

```bash
# Test DNS resolution
kubectl run test-dns --image=busybox --rm -it -- nslookup kubernetes.default

# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# Test service DNS
kubectl run test-svc --image=busybox --rm -it -- \
  nslookup <service-name>.<namespace>.svc.cluster.local
```

### Network Policies

```bash
# List network policies
kubectl get networkpolicies -A

# Describe network policy
kubectl describe networkpolicy <policy-name> -n <namespace>

# Test connectivity with policy
kubectl run test-pod --image=busybox --rm -it -- \
  wget -O- http://<target-service>
```

### CNI Issues

```bash
# Check CNI pods
kubectl get pods -n kube-system | grep -E "calico|flannel|weave"

# Check CNI logs
kubectl logs -n kube-system -l k8s-app=calico-node

# Check network interfaces on node
ip addr show
ip route show
```

## Control Plane Debugging

### API Server

```bash
# Check API server status
kubectl get componentstatuses

# Check API server pod
kubectl get pods -n kube-system -l component=kube-apiserver

# Check API server logs (on control plane node)
sudo journalctl -u kubelet | grep kube-apiserver
# Or
sudo cat /var/log/kubernetes/kube-apiserver.log
```

### etcd

```bash
# Check etcd pod
kubectl get pods -n kube-system -l component=etcd

# Check etcd health
kubectl exec -n kube-system <etcd-pod> -- \
  sh -c "ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health"

# Check etcd status
kubectl exec -n kube-system <etcd-pod> -- \
  sh -c "ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status"
```

### Scheduler

```bash
# Check scheduler pod
kubectl get pods -n kube-system -l component=kube-scheduler

# Check scheduler logs
kubectl logs -n kube-system -l component=kube-scheduler

# Check why pod wasn't scheduled
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 Events
```

### Controller Manager

```bash
# Check controller manager pod
kubectl get pods -n kube-system -l component=kube-controller-manager

# Check controller manager logs
kubectl logs -n kube-system -l component=kube-controller-manager
```

## Performance Debugging

### Resource Usage

```bash
# Node resource usage
kubectl top nodes

# Pod resource usage
kubectl top pods -A

# Pod resource usage by namespace
kubectl top pods --namespace=production
```

### API Server Performance

```bash
# Check API server latency
kubectl get --raw /metrics | grep apiserver_request_duration_seconds

# Check request rates
kubectl get --raw /metrics | grep apiserver_request_total
```

### etcd Performance

```bash
# Check etcd latency
kubectl exec -n kube-system <etcd-pod> -- \
  sh -c "ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  --write-out=table endpoint status"
```

## Debugging Tools

### kubectl debug

```bash
# Create debugging pod
kubectl debug <pod-name> -n <namespace> -it --image=busybox

# Copy files from pod
kubectl cp <namespace>/<pod-name>:/path/to/file ./local-file
kubectl cp ./local-file <namespace>/<pod-name>:/path/to/file
```

### Temporary Debug Pods

```bash
# Run temporary pod for testing
kubectl run debug-pod --image=busybox --rm -it -- sh

# Test service connectivity
kubectl run test-curl --image=curlimages/curl --rm -it -- \
  curl http://<service-name>.<namespace>.svc.cluster.local
```

### Useful Debug Images

- `busybox`: Lightweight shell utilities
- `curlimages/curl`: HTTP testing
- `nicolaka/netshoot`: Network debugging
- `bitnami/kubectl`: kubectl in container

## Debugging Workflows

### Complete Pod Debugging Workflow

```bash
# 1. Get pod status
kubectl get pod <pod-name> -n <namespace>

# 2. Describe pod
kubectl describe pod <pod-name> -n <namespace>

# 3. Check events
kubectl get events --field-selector involvedObject.name=<pod-name> -n <namespace>

# 4. Check logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# 5. Check resource usage
kubectl top pod <pod-name> -n <namespace>

# 6. Interactive debugging
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# 7. Check configuration
kubectl get pod <pod-name> -n <namespace> -o yaml
```

### Complete Service Debugging Workflow

```bash
# 1. Check service
kubectl get svc <service-name> -n <namespace>

# 2. Check endpoints
kubectl get endpoints <service-name> -n <namespace>

# 3. Check pods behind service
kubectl get pods -n <namespace> -l <selector>

# 4. Test DNS
kubectl run test-dns --image=busybox --rm -it -- \
  nslookup <service-name>.<namespace>.svc.cluster.local

# 5. Test connectivity
kubectl run test-curl --image=curlimages/curl --rm -it -- \
  curl http://<service-name>.<namespace>.svc.cluster.local
```

## Tips and Best Practices

1. **Always check events first**: `kubectl get events` often reveals the root cause
2. **Use `-o wide` for more details**: Shows node assignments, IPs, etc.
3. **Check previous container logs**: `--previous` flag for crashed containers
4. **Use `describe` for detailed info**: More verbose than `get`
5. **Test from inside cluster**: Use debug pods to test connectivity
6. **Check resource limits**: Many issues are resource-related
7. **Verify labels and selectors**: Common cause of service issues
8. **Document your debugging**: Helps with future issues

## Additional Resources

- [Kubernetes Troubleshooting Guide](https://kubernetes.io/docs/tasks/debug/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Recovery Procedures](recovery-procedures.md)
- [Architecture Documentation](architecture.md)

