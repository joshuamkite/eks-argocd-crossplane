# EKS Cluster Setup with Monitoring and GitOps

- [EKS Cluster Setup with Monitoring and GitOps](#eks-cluster-setup-with-monitoring-and-gitops)
  - [Prerequisites](#prerequisites)
    - [1. Deploy EKS Cluster](#1-deploy-eks-cluster)
    - [2.Configure Cluster access](#2configure-cluster-access)
    - [3. Install ArgoCD](#3-install-argocd)
    - [4. Access Argo CD UI](#4-access-argo-cd-ui)
    - [5. Access Monitoring Dashboards](#5-access-monitoring-dashboards)
    - [6. Configure Git Repository (Currently unused)](#6-configure-git-repository-currently-unused)
    - [7. Deploy ApplicationSet](#7-deploy-applicationset)
  - [Important Notes](#important-notes)


Set up an EKS cluster with Prometheus and Grafana monitoring, ArgoCd and AWS Applicatio Load Balancer Controller:

## Prerequisites

- AWS CLI configured with appropriate credentials
- kubectl installed
- Helm installed
- Terraform (or OpenTofu) installed


### 1. Deploy EKS Cluster

export TF_VAR_cidr_passlist=${your_ip}$/32
export AWS_ACCOUNT_ID=${account_id}
export AWS_REGION=${region}$
export AWS_PROFILE=${profile}
export GITHUB_TOKEN=${PAT}


### 2.Configure Cluster access

aws eks list-clusters 
aws eks update-kubeconfig --name personal-eks-workshop

### 3. Install ArgoCD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd --namespace argocd --create-namespace
```

### 4. Access Argo CD UI
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Access at: `http://localhost:8080`

Get initial admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### 5. Access Monitoring Dashboards

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

### 6. Configure Git Repository (Currently unused)

Apply configuration:
```bash
envsubst < argocd/config/repo-config.yaml | kubectl apply -f -
```

### 7. Deploy ApplicationSet

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
envsubst < argocd/applicationset/applicationset.yaml | kubectl apply -f -
```

## Important Notes

1. **Security Considerations**:
   - Current setup uses basic IAM user authentication
   - Services are publicly accessible (restricted by NACLs to specific IPs)
   - Using unencrypted HTTP for endpoints
   - Consider using VPN access and proper TLS certificates in production

2. **Resource Management**:
   - Load balancers must be manually deleted before cluster destruction

3. **Production Recommendations**:
   - Implement proper IAM roles instead of IAM users
   - Set up private VPC endpoints
   - Configure TLS certificates using AWS Certificate Manager
   - Use proper DNS aliases for Load Balancer URLs
   - Implement proper backup and disaster recovery procedures

4. **Source Control**:
   - Backend configuration (`backend.tf`) should be managed separately
   - Sensitive information should be managed through secrets management

