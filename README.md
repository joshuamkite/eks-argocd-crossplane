# EKS Cluster Setup with Monitoring and GitOps

- [EKS Cluster Setup with Monitoring and GitOps](#eks-cluster-setup-with-monitoring-and-gitops)
  - [Prerequisites](#prerequisites)
  - [Deploy EKS Cluster](#deploy-eks-cluster)
    - [Configure Cluster access](#configure-cluster-access)
  - [Install ArgoCD](#install-argocd)
    - [Set up port forward access to ArgoCD](#set-up-port-forward-access-to-argocd)
  - [Deploy Monitoring ApplicationSet](#deploy-monitoring-applicationset)
    - [Access Monitoring Dashboards (optional)](#access-monitoring-dashboards-optional)
  - [Crossplane](#crossplane)
    - [Deploy Crossplane **via argoCD**](#deploy-crossplane-via-argocd)
    - [Install the Crossplane AWS S3 provider with IRSA authentication](#install-the-crossplane-aws-s3-provider-with-irsa-authentication)
    - [Create a managed resource (S3 example)](#create-a-managed-resource-s3-example)
    - [Modifying an existing resource](#modifying-an-existing-resource)
    - [Delete the managed resource](#delete-the-managed-resource)
  - [Composite resources and APIs (Crossplane Tutorial part 2)](#composite-resources-and-apis-crossplane-tutorial-part-2)
  - [Accessing the API nosql happens at the cluster scope.](#accessing-the-api-nosql-happens-at-the-cluster-scope)


Set up an EKS cluster with Prometheus and Grafana monitoring, ArgoCd and AWS Applicatio Load Balancer Controller:

## Prerequisites

- AWS CLI configured with appropriate credentials
- kubectl installed
- Helm installed
- Terraform (or OpenTofu) installed

> [!NOTE]
> 
> - **Security Considerations**:
>   - Services are publicly accessible (restricted by NACLs to specific IPs)
>   - Using unencrypted HTTP for endpoints
>   - Consider using VPN access and proper TLS certificates in production
> 
> - **Resource Management**:
>   - Load balancers must be deleted before cluster destruction
> 
> - **Production Recommendations**:
>   - Set up private VPC endpoints
>   - Configure TLS certificates using AWS Certificate Manager
>   - Use proper DNS aliases for Load Balancer URLs
>   - Implement proper backup and disaster recovery procedures
> 
> - **Source Control**:
>   - Backend configuration (`backend.tf`) should be managed separately
>   - Sensitive information should be managed through secrets management

## Deploy EKS Cluster

```bash
export TF_VAR_cidr_passlist=${your_ip}$/32
export AWS_REGION=${region}$
export AWS_PROFILE=${profile}
export CLUSTER_NAME=${cluster_name}
```

### Configure Cluster access
```bash
aws eks list-clusters 
aws eks update-kubeconfig --name personal-eks-workshop
```
## Install ArgoCD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd --namespace argocd --create-namespace
```

### Set up port forward access to ArgoCD 

Get initial admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```
Then
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Login to ArgoCD (CLI)

get password with 
```bash
argocd login localhost:8080 --username admin --password <your-password> --insecure --grpc-web
```

GUI Access (otional) at: `http://localhost:8080`

## Deploy Monitoring ApplicationSet

This application installs:

- Monitoring server
- Prometheus
- Grafana
- AWS Load Balancer Controller

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
envsubst < argocd/applicationset/monitoring-apps.yaml | kubectl apply -f -
```

### Access Monitoring Dashboards (optional)

For Prometheus:
```bash
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 4001:9090
```
Access at: `http://127.0.0.1:4001`

For Grafana:

Get Grafana credentials:
```bash
# Username: admin
# Password:
kubectl get secret --namespace monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```
```bash
kubectl port-forward service/prometheus-grafana 3000:80 --namespace monitoring
```
Access at: http://127.0.0.1:3000

## Crossplane 

### Deploy Crossplane **via argoCD**

The following is partly based on [Crossplane tutorial part 1](https://docs.crossplane.io/latest/getting-started/provider-aws/) but with some notable changes:

- OIDC authentication is substituted for IAM static credentials 
- We are using ArgoCD to install Crossplane rather than Helm directly
- Discrete YAML files are substituted for HereDocs
- We concatenate YAML files where that makes sense
- We demonstrate updating an exiting resource in place

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
envsubst < argocd/applications/crossplane.yaml | argocd app create -f -
```

Verify Crossplane installed with kubectl get pods.

```bash
kubectl get pods -n crossplane-system
```
Installing Crossplane creates new Kubernetes API end-points. check these with 
```bash
kubectl api-resources | grep crossplane
```

### Install the Crossplane AWS S3 provider with IRSA authentication

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
- Check the provider status: 
  ```bash
  kubectl get providers
  ```
- View the new CRDs: 
  ```bash
  kubectl get crds
  ```

### Create a managed resource (S3 example)

A managed resource is anything Crossplane creates and manages outside of the Kubernetes cluster. AWS S3 bucket names must be globally unique. To generate a unique name the example uses a random hash. Any unique name is acceptable.

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

```bash
kubectl get buckets
NAME                      SYNCED   READY   EXTERNAL-NAME             AGE
crossplane-bucket-r8lvj   True     True    crossplane-bucket-r8lvj   109m
```

### Modifying an existing resource

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

### Delete the managed resource 

Before shutting down your Kubernetes cluster, delete the S3 bucket just created.

```bash
kubectl delete bucket ${bucketname}
```

## Composite resources and APIs (Crossplane Tutorial part 2)

based on https://docs.crossplane.io/latest/getting-started/provider-aws-part-2/

Install the DynamoDB Provider 

```bash
kubectl apply -f argocd/applications/crossplane-aws-dynamodb-provider.yaml 
```

Apply the API 

```bash
kubectl apply -f argocd/applications/crossplane-nosql-api.yaml 
```

View the installed XRD with 
```bash
kubectl get xrd
```

View the new custom API endpoints with 
```bashkubectl api-resources | grep nosql
```

```bash
kubectl apply -f argocd/applications/crossplane-dynamo-with-bucket-composition.yaml 
```

Apply this Function to install function-patch-and-transform:

```bash
kubectl apply -f argocd/applications/crossplane-function-patch-and-transform.yaml 
```

View the Composition with 
```bash
kubectl get composition
```

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

View the resource with 
```bash
kubectl get nosql
```

This object is a Crossplane composite resource (also called an XR). It's a single object representing the collection of resources created from the Composition template.

View the individual resources with 
```bash
kubectl get managed
```

Delete the resources with 
```bash
kubectl delete nosql my-nosql-database
```

Verify Crossplane deleted the resources with `kubectl get managed`

Note
It may take up to 5 minutes to delete the resources.

## Accessing the API nosql happens at the cluster scope.
Most organizations isolate their users into namespaces.

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