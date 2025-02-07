# EKS Cluster Setup with Monitoring and GitOps

- [EKS Cluster Setup with Monitoring and GitOps](#eks-cluster-setup-with-monitoring-and-gitops)
  - [Prerequisites](#prerequisites)
  - [Approach 1: Quick Setup with Port Forwarding](#approach-1-quick-setup-with-port-forwarding)
    - [1. Verify Cluster Access](#1-verify-cluster-access)
    - [2. Install Metrics Server](#2-install-metrics-server)
    - [3. Install Prometheus and Grafana](#3-install-prometheus-and-grafana)
    - [4. Access Monitoring Dashboards](#4-access-monitoring-dashboards)
  - [Approach 2: Production Setup with Load Balancer Controller](#approach-2-production-setup-with-load-balancer-controller)
    - [1. Deploy Load Balancer Controller](#1-deploy-load-balancer-controller)
    - [2. Install Monitoring Stack](#2-install-monitoring-stack)
    - [3. Access Services](#3-access-services)
  - [Approach 3: GitOps with Argo CD](#approach-3-gitops-with-argo-cd)
    - [1. Install Argo CD](#1-install-argo-cd)
    - [2. Access Argo CD UI](#2-access-argo-cd-ui)
    - [3. Configure Git Repository](#3-configure-git-repository)
    - [4. Deploy ApplicationSet](#4-deploy-applicationset)
  - [Important Notes](#important-notes)


This guide describes three approaches to deploy an EKS cluster with Prometheus and Grafana monitoring:

1. Quick setup with port forwarding
2. Production-ready setup with AWS Load Balancer Controller
3. GitOps approach using Argo CD

## Prerequisites

- AWS CLI configured with appropriate credentials
- kubectl installed
- Helm installed
- Terraform (or OpenTofu) installed

## Approach 1: Quick Setup with Port Forwarding

This approach is suitable for development and testing environments.

### 1. Verify Cluster Access
```bash
kubectl get pods -n kube-system
```

### 2. Install Metrics Server
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

Verify installation:
```bash
kubectl get pods -n kube-system
kubectl get deployments -n kube-system
```

### 3. Install Prometheus and Grafana
Add Helm repository:
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
```

Install monitoring stack:
```bash
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set alertmanager.persistentVolume.storageClass="gp2",server.persistVolume.storageClass="gp2"
```

### 4. Access Monitoring Dashboards

For Prometheus:
```bash
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 4001:9090
```
Access at: `http://127.0.0.1:4001`

For Grafana:
```bash
kubectl port-forward service/prometheus-grafana 3000:80 --namespace monitoring
```
Access at: `http://127.0.0.1:3000`

Get Grafana credentials:
```bash
# Username: admin
# Password:
kubectl get secret --namespace monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```

## Approach 2: Production Setup with Load Balancer Controller

This approach is suitable for production environments, providing external access through AWS Load Balancers.

### 1. Deploy Load Balancer Controller

Create service account:
```bash
kubectl apply -f helm/aws-load-balancer-controller-sa.yaml
```

Install controller:
```bash
helm repo add eks https://aws.github.io/eks-charts

helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=personal-eks-workshop \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### 2. Install Monitoring Stack

Install metrics server and Prometheus/Grafana:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set alertmanager.persistentVolume.storageClass="gp2",server.persistVolume.storageClass="gp2" \
  --values grafana-prometheus-custom-values.yaml
```

### 3. Access Services

Get Load Balancer URLs:
```bash
kubectl get svc -n monitoring
```

Access format: `http://<LoadBalancer-Ingress>:<PORT>`

- Prometheus: Port 9090
- Grafana: Default HTTP port (80)

## Approach 3: GitOps with Argo CD

### 1. Install Argo CD
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd --namespace argocd --create-namespace
```

### 2. Access Argo CD UI
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Access at: `http://localhost:8080`

Get initial admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### 3. Configure Git Repository

Apply configuration:
```bash
kubectl apply -f argocd/config/repo-config.yaml
```

### 4. Deploy ApplicationSet
```bash
kubectl apply -f applicationset.yaml -n argocd
```

## Important Notes

1. **Security Considerations**:
   - Current setup uses basic IAM user authentication
   - Services are publicly accessible (restricted by NACLs to specific IPs)
   - Using unencrypted HTTP for endpoints
   - Consider using VPN access and proper TLS certificates in production

2. **Resource Management**:
   - Load balancers must be manually deleted before cluster destruction
   - Use `helm uninstall prometheus -n monitoring` before running `terraform destroy`

3. **Production Recommendations**:
   - Implement proper IAM roles instead of IAM users
   - Set up private VPC endpoints
   - Configure TLS certificates using AWS Certificate Manager
   - Use proper DNS aliases for Load Balancer URLs
   - Implement proper backup and disaster recovery procedures

4. **Source Control**:
   - Backend configuration (`backend.tf`) should be managed separately
   - Sensitive information should be managed through secrets management