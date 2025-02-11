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
    - [8. Login to ArgoCD (CLI)](#8-login-to-argocd-cli)
    - [9 . Deploy Crossplane **via argoCD**](#9--deploy-crossplane-via-argocd)
    - [10. Crossplane tutorial part 1 - Install the AWS S3 provider with IRSA authentication](#10-crossplane-tutorial-part-1---install-the-aws-s3-provider-with-irsa-authentication)
    - [Create a managed resource](#create-a-managed-resource)
    - [Modify existing resource](#modify-existing-resource)
- [Tutorial part 2](#tutorial-part-2)
  - [Accessing the API nosql at the cluster scope](#accessing-the-api-nosql-at-the-cluster-scope)


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
export CLUSTER_NAME=${cluster_name}


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

Get initial admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Access at: `http://localhost:8080`


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
envsubst < argocd/applicationset/monitoring-apps.yaml | kubectl apply -f -
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

### 8. Login to ArgoCD (CLI)

get password with 
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

argocd login localhost:8080 --username admin --password <your-password> --insecure --grpc-web

### 9 . Deploy Crossplane **via argoCD**

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
envsubst < argocd/applications/crossplane.yaml | argocd app create -f -
```

Verify Crossplane installed with kubectl get pods.

```bash
kubectl get pods -n crossplane-system
```

Installing Crossplane creates new Kubernetes API end-points. Look at the new API end-points with `kubectl api-resources | grep crossplane`

### 10. Crossplane tutorial part 1 - Install the AWS S3 provider with IRSA authentication

Partly based on https://docs.crossplane.io/latest/getting-started/provider-aws/

The Crossplane Provider installs the Kubernetes Custom Resource Definitions (CRDs) representing AWS S3 services. These CRDs allow you to create AWS resources directly inside Kubernetes.

To install the AWS S3 provider with IRSA (IAM Roles for Service Accounts) authentication, we need three components:

1. A DeploymentRuntimeConfig that configures the provider to use our service account with IRSA annotations
2. The Provider itself that installs the AWS S3 CRDs
3. A ProviderConfig that tells Crossplane to use IRSA authentication

Apply all three components with:

```bash
kubectl apply -f argocd/applications/crossplane-aws-s3-provider-setup.yaml
```

The configuration file contains:
- DeploymentRuntimeConfig: Ensures the provider uses our IRSA-annotated service account instead of auto-creating its own
- Provider: Installs the AWS S3 provider from Upbound's registry
- ProviderConfig: Configures the provider to use IRSA authentication

Verify the installation:
- Check the provider status: `kubectl get providers`
- View the new CRDs: `kubectl get crds`

### Create a managed resource 
A managed resource is anything Crossplane creates and manages outside of the Kubernetes cluster.

This guide creates an AWS S3 bucket with Crossplane.

The S3 bucket is a managed resource.

AWS S3 bucket names must be globally unique. To generate a unique name the example uses a random hash. Any unique name is acceptable.

```bash
cat <<EOF | kubectl create -f -
apiVersion: s3.aws.upbound.io/v1beta1
kind: Bucket
metadata:
  generateName: crossplane-bucket-
spec:
  forProvider:
    region: eu-west-1
  providerConfigRef:
    name: default
EOF
```

Verifiying resource creation

We can see that the bucket is deployed when `SYNCED` and `READY` are both `True`

```yaml
kubectl get buckets
NAME                      SYNCED   READY   EXTERNAL-NAME             AGE
crossplane-bucket-r8lvj   True     True    crossplane-bucket-r8lvj   109m
```

### Modify existing resource

Ensure correct bucket name

```bash
cat <<EOF | kubectl apply -f -
apiVersion: s3.aws.upbound.io/v1beta1
kind: Bucket
metadata:
  name: crossplane-bucket-r8lvj
spec:
  forProvider:
    region: eu-west-1
    tags:
      project: crossplane-demo
      deployment: manual
  providerConfigRef:
    name: default
EOF
```

Delete the managed resource 
Before shutting down your Kubernetes cluster, delete the S3 bucket just created.

```bash
kubectl delete bucket ${bucketname}
```

# Tutorial part 2

based on https://docs.crossplane.io/latest/getting-started/provider-aws-part-2/

Install the DynamoDB Provider 

```bash
kubectl apply -f argocd/applications/crossplane-aws-dynamodb-provider.yaml 
```

Apply the API 

```bash
kubectl apply -f argocd/applications/crossplane-nosql-api.yaml 
```

View the installed XRD with `kubectl get xrd`.

View the new custom API endpoints with `kubectl api-resources | grep nosql`

```bash
kubectl apply -f argocd/applications/crossplane-dynamo-with-bucket-composition.yaml 
```

Apply this Function to install function-patch-and-transform:

```bash
kubectl apply -f argocd/applications/crossplane-function-patch-and-transform.yaml 
```

View the Composition with `kubectl get composition`

Create a NoSQL object to create the cloud resources.

```yaml
cat <<EOF | kubectl apply -f -
apiVersion: database.example.com/v1alpha1
kind: NoSQL
metadata:
  name: my-nosql-database
spec: 
  location: "US"
EOF
```

View the resource with `kubectl get nosql`.


This object is a Crossplane composite resource (also called an XR).
It’s a single object representing the collection of resources created from the Composition template.

View the individual resources with `kubectl get managed`

Delete the resources with `kubectl delete nosql my-nosql-database`
`

Verify Crossplane deleted the resources with `kubectl get managed`

Note
It may take up to 5 minutes to delete the resources.

## Accessing the API nosql at the cluster scope

Organizations may isolate their users into namespaces.

A Crossplane Claim is the custom API in a namespace.

Creating a Claim is just like accessing the custom API endpoint, but with the kind from the custom API’s claimNames.

Create a new namespace to test create a Claim in.

`kubectl create namespace crossplane-test`

Then create a Claim in the crossplane-test namespace.

```yaml
cat <<EOF | kubectl apply -f -
apiVersion: database.example.com/v1alpha1
kind: NoSQLClaim
metadata:
  name: my-nosql-database
  namespace: crossplane-test
spec: 
  location: "US"
EOF
```

View the Claim with `kubectl get claim -n crossplane-test`

The Claim automatically creates a composite resource, which creates the managed resources.

View the Crossplane created composite resource with `kubectl get composite`

Again, view the managed resources with `kubectl get managed`

Deleting the Claim deletes all the Crossplane generated resources.

`kubectl delete claim -n crossplane-test my-nosql-database`

Note
It may take up to 5 minutes to delete the resources.

Verify Crossplane deleted the composite resource with `kubectl get composite`

Verify Crossplane deleted the managed resources with `kubectl get managed`