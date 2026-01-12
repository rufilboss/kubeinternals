# Kubernetes Internals: Build & Break a Production-Grade Cluster

> **"If the control plane goes down, the company stops making money."**

A comprehensive hands-on project demonstrating deep Kubernetes internals knowledge, cluster resilience, and production-grade debugging skills. This project showcases the ability to build, operate, and recover a Kubernetes cluster from scratch.

## 🎯 Project Overview

This project demonstrates:

- **Cluster Architecture**: Building a Kubernetes cluster from scratch using kubeadm
- **Production Services**: Deploying API services, worker services, and stateful databases
- **Resilience Engineering**: Handling pod evictions, node failures, and control plane disasters
- **Operational Excellence**: etcd backup/restore, debugging CrashLoopBackOff, manual scaling
- **Business Impact**: Understanding the criticality of control plane availability

## 📋 Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Cluster Setup](#cluster-setup)
- [Service Deployment](#service-deployment)
- [Failure Scenarios](#failure-scenarios)
- [Recovery Procedures](#recovery-procedures)
- [Debugging Guide](#debugging-guide)
- [Business Impact Analysis](#business-impact-analysis)

## 🏗️ Architecture

### Cluster Topology

```sh
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Control Plane Node                      │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐          │   │
│  │  │ API      │  │ etcd     │  │ Scheduler│          │   │
│  │  │ Server   │  │          │  │          │          │   │
│  │  └──────────┘  └──────────┘  └──────────┘          │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐          │   │
│  │  │ Controller│ │ Cloud    │  │ Kubelet  │          │   │
│  │  │ Manager  │  │ Controller│ │          │          │   │
│  │  └──────────┘  └──────────┘  └──────────┘          │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Worker Node 1                            │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐          │   │
│  │  │ API      │  │ Worker   │  │ Redis    │          │   │
│  │  │ Service  │  │ Service  │  │          │          │   │
│  │  └──────────┘  └──────────┘  └──────────┘          │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Worker Node 2                            │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐          │   │
│  │  │ API      │  │ Worker   │  │ PostgreSQL│         │   │
│  │  │ Service  │  │ Service  │  │          │          │   │
│  │  └──────────┘  └──────────┘  └──────────┘          │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Component Details

- **Control Plane**: Single master node (can be extended to HA)
- **Worker Nodes**: 2+ worker nodes for high availability
- **API Service**: RESTful API with health checks and resource limits
- **Worker Service**: Background job processor with queue integration
- **Redis**: In-memory cache and message queue
- **PostgreSQL**: Persistent relational database

## 📦 Prerequisites

### System Requirements

- **3+ Virtual Machines** or physical machines:
  - 1 Control Plane Node: 2+ CPU, 2GB+ RAM
  - 2+ Worker Nodes: 2+ CPU, 2GB+ RAM each
- **Operating System**: Ubuntu 20.04+ / CentOS 7+ / RHEL 8+
- **Network**: All nodes must be able to communicate

### Software Requirements

- Docker 20.10+
- kubeadm 1.28+
- kubectl 1.28+
- kubelet 1.28+
- Container runtime (containerd or Docker)

### Alternative: Local Development

For local testing, you can use `kind` (Kubernetes in Docker) - see `docs/kind-setup.md`

## 🚀 Quick Start

### 1. Initialize Control Plane

```bash
# On control plane node
sudo ./scripts/setup-control-plane.sh
```

### 2. Join Worker Nodes

```bash
# On each worker node (use token from control plane)
sudo ./scripts/join-worker-node.sh <token> <discovery-token-ca-cert-hash>
```

### 3. Deploy Services

```bash
# From your local machine (with kubectl configured)
kubectl apply -f manifests/
```

### 4. Verify Deployment

```bash
kubectl get nodes
kubectl get pods -A
kubectl get svc -A
```

## 📁 Project Structure

```sh
kubeinternals/
├── README.md                 # This file
├── LICENSE
├── manifests/                # Kubernetes manifests
│   ├── api-service/         # API service deployment
│   ├── worker-service/      # Worker service deployment
│   ├── redis/               # Redis deployment
│   ├── postgresql/          # PostgreSQL deployment
│   └── namespace.yaml       # Namespace definitions
├── scripts/                  # Automation scripts
│   ├── setup-control-plane.sh
│   ├── join-worker-node.sh
│   ├── etcd-backup.sh
│   ├── etcd-restore.sh
│   ├── simulate-failures.sh
│   └── load-test.sh
├── configs/                  # Configuration files
│   ├── kubeadm-config.yaml
│   ├── containerd-config.toml
│   └── kubelet-config.yaml
├── docs/                     # Documentation
│   ├── architecture.md      # Detailed architecture
│   ├── recovery-procedures.md
│   ├── debugging-guide.md
│   ├── etcd-operations.md
│   └── kind-setup.md        # Local development setup
└── diagrams/                 # Architecture diagrams
    └── cluster-architecture.png
```

## 🔧 Cluster Setup

### Manual Setup with kubeadm

See [docs/cluster-setup.md](docs/cluster-setup.md) for detailed instructions.

### Key Configuration Points

- **Pod Network**: Calico CNI plugin
- **Container Runtime**: containerd
- **API Server**: Configured for HA (ready for expansion)
- **etcd**: Single node (production should use HA)

## 🚢 Service Deployment

### API Service

- **Replicas**: 3 (for high availability)
- **Resource Limits**: CPU: 500m, Memory: 512Mi
- **Probes**: Liveness and readiness checks
- **Service Type**: ClusterIP (with optional LoadBalancer)

### Worker Service

- **Replicas**: 2
- **Resource Limits**: CPU: 1000m, Memory: 1Gi
- **Queue Integration**: Redis-based job queue
- **Graceful Shutdown**: Handles SIGTERM properly

### Redis

- **StatefulSet**: Persistent storage
- **Resource Limits**: CPU: 500m, Memory: 1Gi
- **Persistence**: PVC with 10Gi storage

### PostgreSQL

- **StatefulSet**: Persistent storage
- **Resource Limits**: CPU: 1000m, Memory: 2Gi
- **Persistence**: PVC with 20Gi storage
- **Backup**: Automated daily backups

## 💥 Failure Scenarios

This project includes scripts to simulate and handle:

1. **Pod Eviction**: Memory/CPU pressure causing pod evictions
2. **Node Failure**: Complete worker node failure
3. **Control Plane Failure**: API server, etcd, or scheduler failure
4. **CrashLoopBackOff**: Application crashes and recovery
5. **Network Partition**: Split-brain scenarios
6. **Resource Exhaustion**: CPU/Memory starvation

See [docs/failure-scenarios.md](docs/failure-scenarios.md) for details.

## 🔄 Recovery Procedures

### etcd Backup & Restore

```bash
# Backup etcd
./scripts/etcd-backup.sh

# Restore etcd from backup
./scripts/etcd-restore.sh <backup-file>
```

See [docs/recovery-procedures.md](docs/recovery-procedures.md) for complete recovery guide.

### Cluster Recovery Steps

1. **Identify Failure**: Use kubectl and logs to diagnose
2. **Isolate Impact**: Determine affected components
3. **Execute Recovery**: Follow procedure-specific steps
4. **Verify Health**: Confirm cluster and services are operational
5. **Document**: Record root cause and prevention measures

## 🐛 Debugging Guide

### Common Issues

- **CrashLoopBackOff**: See [docs/debugging-guide.md#crashloopbackoff](docs/debugging-guide.md#crashloopbackoff)
- **Pod Stuck in Pending**: Resource constraints or node issues
- **Service Not Accessible**: Network policies or service configuration
- **etcd Issues**: Quorum loss or corruption

### Debugging Commands

```bash
# Check pod status
kubectl describe pod <pod-name>
kubectl logs <pod-name>

# Check node status
kubectl get nodes -o wide
kubectl describe node <node-name>

# Check events
kubectl get events --sort-by='.lastTimestamp'

# Check resource usage
kubectl top nodes
kubectl top pods
```

See [docs/debugging-guide.md](docs/debugging-guide.md) for comprehensive debugging procedures.

## 💼 Business Impact Analysis

### Control Plane Availability

**Scenario**: Control plane goes down during business hours

**Impact**:
- No new pods can be scheduled
- Existing pods continue running but cannot be managed
- Service discovery may be affected
- No scaling, updates, or deployments possible

**Recovery Time Objective (RTO)**: < 15 minutes
**Recovery Point Objective (RPO)**: < 5 minutes (etcd backup frequency)

### Cost of Downtime

- **Revenue Loss**: $X per minute of downtime
- **Customer Impact**: Service degradation or unavailability
- **Reputation**: Loss of trust in platform reliability

### Mitigation Strategies

1. **HA Control Plane**: 3+ control plane nodes
2. **Regular Backups**: Automated etcd backups every 5 minutes
3. **Monitoring**: Real-time alerts for control plane health
4. **Runbooks**: Documented recovery procedures
5. **Disaster Recovery**: Tested restore procedures

## 📊 Monitoring & Observability

### Key Metrics to Monitor

- Control plane component health
- etcd performance and quorum status
- Node resource utilization
- Pod eviction rates
- API server latency
- Scheduler queue depth

### Recommended Tools

- Prometheus + Grafana
- kubectl top
- Kubernetes Dashboard
- Custom health check endpoints

## 🧪 Testing

### Load Testing

```bash
# Simulate load on API service
./scripts/load-test.sh api-service 1000
```

### Failure Injection

```bash
# Simulate node failure
./scripts/simulate-failures.sh node-failure worker-node-1
```

## 📚 Additional Resources

- [Kubernetes Official Documentation](https://kubernetes.io/docs/)
- [etcd Operations Guide](https://etcd.io/docs/)
- [kubeadm Documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)

## 🤝 Contributing

This is a learning project. Feel free to:

- Report issues
- Suggest improvements
- Add more failure scenarios
- Enhance documentation

## 📝 License

MIT License - See [LICENSE](LICENSE) file for details

## 👤 Author

**Ilyas Rufai**

---

## 🎓 Learning Outcomes

After completing this project, you will understand:

✅ Kubernetes cluster architecture and components  
✅ Control plane internals (API server, etcd, scheduler)  
✅ Pod lifecycle and resource management  
✅ Stateful vs stateless workloads  
✅ Failure recovery and disaster procedures  
✅ Production-grade debugging techniques  
✅ Business impact of infrastructure failures  

**This project demonstrates the skills needed for senior DevOps/SRE roles at FAANG companies.**
