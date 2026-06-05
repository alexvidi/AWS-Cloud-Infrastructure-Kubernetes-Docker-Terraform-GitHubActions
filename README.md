# FastAPI on AWS with Terraform, EKS, and GitHub Actions

[![Terraform](https://img.shields.io/badge/IaC-Terraform-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/Cloud-AWS-FF9900?logo=amazonaws&logoColor=white)](https://aws.amazon.com/)
[![Kubernetes](https://img.shields.io/badge/Orchestration-Kubernetes-326CE5?logo=kubernetes)](https://kubernetes.io/)
[![FastAPI](https://img.shields.io/badge/Framework-FastAPI-009688?logo=fastapi)](https://fastapi.tiangolo.com/)

## Overview

This repository contains a cloud-native deployment project that takes a small FastAPI market quote service from source code to a production-style runtime on AWS.

The application itself is intentionally simple. The focus of the repository is the delivery platform around it:

- AWS infrastructure provisioned with Terraform
- Docker image build and publish to Amazon Elastic Container Registry (ECR)
- application runtime on Amazon Elastic Kubernetes Service (EKS)
- Kubernetes deployment with Ingress, autoscaling, network restrictions, and disruption controls
- CI/CD validation and deployment with GitHub Actions over OIDC (no static AWS keys)
- Prometheus metrics, Alertmanager email alerts, and Grafana dashboards

The project is deliberately scoped to stay coherent. Features that were not justified by the current workload were left out so the repository reflects the technologies that are actually being used.

> This is the AWS counterpart of an equivalent Azure (AKS) project. The application, Kubernetes manifests, and observability stack are shared; the cloud-specific layer (network, registry, managed Kubernetes, identity, CI/CD auth) is rebuilt for AWS.

## At a Glance

| Area | Implementation |
| --- | --- |
| Cloud | AWS VPC, ECR, EKS, CloudWatch (control plane logs) |
| IaC | Modular Terraform on top of the official `vpc` and `eks` AWS modules, with remote state in S3 |
| Containerization | Dockerized FastAPI app running as non-root |
| Kubernetes | Namespace, Deployment, Service, Ingress, HPA, NetworkPolicy, PDB, raw monitoring manifests |
| Packaging | Raw Kubernetes manifests |
| CI/CD | GitHub Actions validate and deploy workflows, authenticated to AWS via OIDC |
| Security | Pod Security Admission, container hardening, VPC CNI NetworkPolicy enforcement, IAM least privilege, Trivy, Checkov |
| Observability | Prometheus + Alertmanager + Grafana via raw Kubernetes manifests |

## Architecture

### Runtime Request Flow

```text
Client
  -> ingress-nginx LoadBalancer (AWS ELB)
  -> Ingress
  -> ClusterIP Service
  -> FastAPI Pod
  -> /health or /quote response
```

### Delivery Flow

```text
Push to master
  -> GitHub Actions Validate workflow
  -> GitHub Actions Deploy workflow when Validate succeeds and the commit
     changes application runtime files or Kubernetes manifests

Deploy workflow
  -> Detect deploy-relevant changes
  -> Assume AWS role via OIDC
  -> Docker build
  -> Trivy image scan
  -> Push image to ECR
  -> Ensure ingress-nginx controller exists
  -> kubectl apply manifests to EKS
  -> Update Deployment image to commit SHA
  -> Wait for rollout completion
  -> Smoke test /health and /quote
```

## Key Technical Decisions

- **Simple application, real platform concerns**
  The API is intentionally lightweight so the repository can focus on infrastructure, deployment, security, and operations.

- **Terraform modules instead of a flat root configuration**
  AWS infrastructure is split into `network`, `registry`, `eks`, and `github-oidc` modules. The `network` and `eks` modules wrap the well-maintained `terraform-aws-modules` so the platform stays small and correct instead of re-implementing a VPC and an EKS cluster by hand.

- **EKS with VPC CNI NetworkPolicy enforcement**
  The AWS VPC CNI add-on is configured with `enableNetworkPolicy = "true"` so the application `NetworkPolicy` is actually enforced. Without this, EKS would silently ignore NetworkPolicies.

- **ingress-nginx instead of the AWS Load Balancer Controller (for now)**
  The application is exposed through the `ingress-nginx` controller, which provisions an AWS load balancer for its Service. This keeps the manifests identical to the Azure version and avoids the extra IRSA + controller setup. Moving to the AWS Load Balancer Controller (ALB + IRSA) is a natural next iteration.

- **Image pulls without IRSA**
  The managed node group's IAM role carries `AmazonEC2ContainerRegistryReadOnly`, so pods pull from ECR without per-pod IAM roles. IRSA is kept available (the cluster OIDC provider exists) for workloads that genuinely need scoped AWS access later.

- **Keyless CI/CD with OIDC and EKS Access Entries**
  GitHub Actions assumes an IAM role through OIDC instead of using long-lived access keys. That role is granted `kubectl` access through a native EKS **Access Entry** (cluster-admin), not the legacy `aws-auth` ConfigMap.

- **Baseline runtime hardening**
  The Deployment runs as non-root, disables privilege escalation, drops Linux capabilities, and uses Pod Security Admission in `restricted` mode.

- **Restrictive network posture**
  The application `NetworkPolicy` allows ingress only from the `ingress-nginx` and `monitoring` namespaces on the application port, and denies all egress because the current API does not require outbound network access.

- **Availability controls**
  The project includes an HPA for CPU-based scaling and a PDB to avoid all replicas being voluntarily disrupted at once.

- **No unnecessary platform features**
  GitOps controllers, certificate automation, databases, and tracing were intentionally left out to keep the repository focused and technically consistent.

## Repository Structure

```text
app/                FastAPI application and Dockerfile
infra/              Terraform root and modules (network, registry, eks, github-oidc)
k8s/                Raw Kubernetes manifests
.github/workflows/  Validation and deployment pipelines
```

## Main Components

### Application

The API is implemented in [app/main.py](app/main.py).

Endpoints:

- `GET /health` — used by Kubernetes probes and operational checks.
- `GET /quote?symbol=BTC` — returns a synthetic market quote for a supported symbol.
- `GET /metrics` — exposed for Prometheus scraping.

The business logic is intentionally lightweight and explicit. The API returns synthetic quotes for a small supported symbol set so the repository can emphasize cloud delivery and runtime operations.

### Infrastructure

Terraform lives under [infra/](infra).

Main modules:

- `network` — a VPC with public and private subnets across two AZs and a single NAT gateway (wraps `terraform-aws-modules/vpc/aws`).
- `registry` — an ECR repository with scan-on-push and a lifecycle policy.
- `eks` — an EKS cluster with a private managed node group, VPC CNI NetworkPolicy enforcement, and control plane logs to CloudWatch (wraps `terraform-aws-modules/eks/aws`).
- `github-oidc` — the GitHub OIDC provider and a least-privilege IAM role for CI/CD.

The composition happens in [infra/main.tf](infra/main.tf). After the modules, two EKS Access Entry resources grant the GitHub Actions role cluster-admin, which is the AWS equivalent of an Azure RBAC role assignment.

### Kubernetes

Raw manifests live in [k8s/](k8s): namespace, deployment, service, ingress, hpa, networkpolicy, pdb, and the monitoring stack (Prometheus, Alertmanager, Grafana). These manifests are shared with the Azure version of the project; only the Deployment image reference differs (ECR instead of ACR).

### CI/CD

#### Validation Workflow

[.github/workflows/validate.yml](.github/workflows/validate.yml) runs `ruff`, `pytest`, `bandit`, `pip-audit`, `terraform fmt`, `terraform validate`, `checkov`, and `kubeconform`.

#### Deploy Workflow

[.github/workflows/deploy.yml](.github/workflows/deploy.yml) authenticates to AWS via OIDC, then builds, scans (Trivy), and pushes the image to ECR, ensures `ingress-nginx` exists, applies the manifests to EKS, sets the Deployment image to the validated commit SHA, and runs a post-deploy smoke test against `/health` and `/quote`.

Required GitHub Secrets:

- `AWS_ROLE_ARN` — the IAM role GitHub Actions assumes (Terraform output `github_actions_role_arn`)
- `EKS_CLUSTER_NAME` — the cluster name (Terraform output `eks_cluster_name`)
- `GRAFANA_ADMIN_USER`
- `GRAFANA_ADMIN_PASSWORD`
- `ALERTMANAGER_SMTP_PASSWORD`

The AWS region is set as an environment variable in the workflow (`AWS_REGION`, default `us-east-1`).

### Observability

The application exposes Prometheus metrics at `/metrics`. The monitoring stack (Prometheus, Alertmanager, Grafana) is deployed with raw manifests into the `monitoring` namespace. Grafana is provisioned from ConfigMaps (datasource + dashboard), and Prometheus evaluates two baseline alerting rules (`MarketQuoteApiDown`, `MarketQuoteApiHighServerErrorRate`). Grafana admin credentials and the Alertmanager SMTP password are created as Kubernetes Secrets outside the repo.

## Security Posture

- non-root container runtime, pod and container `securityContext`
- Pod Security Admission in `restricted` mode for the application namespace
- `allowPrivilegeEscalation: false` and dropped Linux capabilities
- resource requests and limits
- `NetworkPolicy` with denied egress by default, enforced by the VPC CNI
- managed node group IAM role limited to ECR read for image pulls
- GitHub Actions authenticated via OIDC with a least-privilege IAM role; cluster access granted via EKS Access Entries
- Grafana and Alertmanager credentials externalized into Kubernetes Secrets
- Trivy image scanning and Checkov IaC scanning in CI

## How to Run

### 1. Prepare the Terraform Remote State (one time)

The backend in [infra/backend.tf](infra/backend.tf) stores state in S3 with native locking (`use_lockfile`, Terraform 1.10+). Create the bucket once:

```bash
aws s3api create-bucket --bucket alexdevops99-tfstate --region us-east-1
aws s3api put-bucket-versioning --bucket alexdevops99-tfstate \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket alexdevops99-tfstate \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

### 2. Provision AWS Infrastructure

Copy the example variables and set your repository:

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set github_repository = "<owner>/<repo>"

terraform init
terraform plan
terraform apply
cd ..
```

Note the outputs: `ecr_repository_url`, `eks_cluster_name`, `github_actions_role_arn`, and `configure_kubectl`.

### 3. Build and Push the Image

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY=$ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin $REGISTRY

docker build -t $REGISTRY/market-quote-api:v1 app
docker push $REGISTRY/market-quote-api:v1
```

### 4. Connect kubectl to EKS

```bash
aws eks update-kubeconfig --region us-east-1 --name alexdevops99-eks
```

### 5. Deploy to Kubernetes

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/cloud/deploy.yaml
kubectl rollout status -n ingress-nginx deployment/ingress-nginx-controller --timeout=180s
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/monitoring-namespace.yaml
kubectl create secret generic grafana-admin \
  -n monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='<strong-password>' \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic alertmanager-smtp \
  -n monitoring \
  --from-literal=smtp-password='<smtp-app-password>' \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f k8s/
kubectl rollout restart -n monitoring deployment/prometheus-server deployment/alertmanager
```

For direct `kubectl apply`, update the image reference in [k8s/deployment.yaml](k8s/deployment.yaml) to your ECR repository, or rely on the deploy workflow which sets it to the validated commit SHA.

### 6. Access the Application

After the `ingress-nginx` Service receives an AWS load balancer hostname, the API is reachable through it (the Ingress omits a host name to keep the demo simple). In a production-style setup, a DNS record would point a domain at the load balancer and TLS would be configured on the Ingress.

### 7. Access Observability

```bash
kubectl port-forward -n monitoring svc/prometheus-server 9090:9090
kubectl port-forward -n monitoring svc/alertmanager 9093:9093
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

Then open `http://127.0.0.1:9090` (Prometheus), `http://127.0.0.1:9093` (Alertmanager), and `http://127.0.0.1:3000` (Grafana).

### 8. Tear Down

EKS bills the control plane per hour and is not in the AWS free tier. Destroy the environment when you are done:

```bash
cd infra
terraform destroy
```

> Delete any load balancers created by `ingress-nginx` first (`kubectl delete -f .../ingress-nginx/.../cloud/deploy.yaml`) so Terraform can remove the VPC cleanly.

## Cost Note

The EKS control plane costs roughly $0.10/hour plus the node instances, and is **not** covered by the AWS free tier. This project is designed to be applied, demonstrated, and destroyed in the same session to keep cost negligible.

## Author

**Alexandre Vidal**
Email: alexvidaldepalol@gmail.com
[LinkedIn](https://www.linkedin.com/in/alexandre-vidal-de-palol-a18538155/)
[GitHub](https://github.com/alexvidi)
