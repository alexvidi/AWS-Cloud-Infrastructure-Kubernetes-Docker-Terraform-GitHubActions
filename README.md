# FastAPI on AWS with Terraform, EKS, and GitHub Actions

[![Validate](https://github.com/alexvidi/AWS-Cloud-Infrastructure-Kubernetes-Docker-Terraform-GitHubActions/actions/workflows/validate.yml/badge.svg?branch=master)](https://github.com/alexvidi/AWS-Cloud-Infrastructure-Kubernetes-Docker-Terraform-GitHubActions/actions/workflows/validate.yml)
[![Terraform](https://img.shields.io/badge/IaC-Terraform-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/Cloud-AWS-FF9900?logo=amazonaws&logoColor=white)](https://aws.amazon.com/)
[![Kubernetes](https://img.shields.io/badge/Orchestration-Kubernetes-326CE5?logo=kubernetes)](https://kubernetes.io/)

**A production-style delivery platform for a small FastAPI service: Terraform-provisioned AWS infrastructure, keyless OIDC CI/CD, hardened Kubernetes on EKS, and Prometheus/Alertmanager/Grafana observability — deployed end-to-end and fully documented below.**

The application is intentionally simple; the focus of this repository is the platform around it. Features that were not justified by the current workload were deliberately left out so the repository reflects the technologies that are actually being used.

> **Project status:** the AWS environment is provisioned and destroyed per validated run to control cost (the EKS control plane bills hourly and has no free tier). The complete end-to-end run is documented in [Proof of Run](#proof-of-run) and the [Full Run Gallery](#full-run-gallery).

![Project flow overview](docs/project-flow-overview.svg)

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

## Proof of Run

<table>
  <tr>
    <td width="50%">
      <img src="docs/screenshots/ci-deploy-workflow.png" alt="Deploy workflow" width="100%"/><br/>
      <sub><b>CI/CD:</b> build → Trivy scan → ECR push → EKS rollout → smoke test, all green.</sub>
    </td>
    <td width="50%">
      <img src="docs/screenshots/infra-eks-cluster-overview.png" alt="EKS cluster overview" width="100%"/><br/>
      <sub><b>EKS:</b> cluster <code>Active</code> on Kubernetes 1.31, healthy control plane, zero health issues.</sub>
    </td>
  </tr>
  <tr>
    <td width="50%">
      <img src="docs/screenshots/obs-grafana-dashboard.png" alt="Grafana dashboard" width="100%"/><br/>
      <sub><b>Observability:</b> live request rate, p95 latency, and status-code metrics in Grafana.</sub>
    </td>
    <td width="50%">
      <img src="docs/screenshots/app-quote-btc.png" alt="Quote endpoint" width="100%"/><br/>
      <sub><b>Application:</b> <code>/quote</code> served through the Kubernetes ingress and AWS load balancer.</sub>
    </td>
  </tr>
</table>

## Architecture

### Runtime Request Flow

```mermaid
flowchart LR
    client(("Client")) --> elb["AWS ELB"]
    elb --> ctrl["ingress-nginx"]
    ctrl --> svc["ClusterIP Service"]
    svc --> pod["FastAPI Pods ×2<br/>(HPA scales 2–5)"]
```

### Delivery Flow

```mermaid
flowchart TD
    A["Push to master"] --> B["Validate workflow<br/>ruff · pytest · bandit · pip-audit<br/>terraform fmt + validate · checkov · kubeconform"]
    B -->|"success"| C{"Runtime files or<br/>k8s manifests changed?"}
    C -->|"no"| S["Skip deploy"]
    C -->|"yes"| D["Assume AWS role via OIDC"]
    D --> E["Docker build"] --> F["Trivy scan<br/>(fails on HIGH / CRITICAL)"]
    F --> G["Push to ECR — tag = commit SHA"]
    G --> H["Ensure ingress-nginx + metrics-server"]
    H --> I["kubectl apply k8s/"] --> J["Set Deployment image to SHA"]
    J --> K["Wait for rollout"] --> L["Smoke test /health + /quote"]
```

### Network Topology

```mermaid
flowchart TB
    inet(("Internet")) --> elb
    subgraph vpc["VPC 10.10.0.0/16 — two AZs, us-east-1"]
        subgraph pub["Public subnets · 10.10.128.0/20 · 10.10.144.0/20"]
            elb["ELB (ingress-nginx)"]
            nat["NAT Gateway (single)"]
        end
        subgraph priv["Private subnets · 10.10.0.0/20 · 10.10.16.0/20"]
            nodes["EKS managed node group<br/>2–4 × t3.medium"]
        end
        elb --> nodes
        nodes --> nat
    end
    nodes <--> cp["EKS control plane (AWS-managed)"]
    nat --> ecr["ECR — KMS-encrypted, immutable tags"]
    cp --> cw["CloudWatch Logs<br/>api · audit · authenticator"]
```

## Key Technical Decisions

- **Simple application, real platform concerns**
  The API is intentionally lightweight so the repository can focus on infrastructure, deployment, security, and operations.

- **Terraform modules instead of a flat root configuration**
  AWS infrastructure is split into `network`, `registry`, `eks`, and `github-oidc` modules. The `network` and `eks` modules wrap the well-maintained `terraform-aws-modules` so the platform stays small and correct instead of re-implementing a VPC and an EKS cluster by hand.

- **EKS with VPC CNI NetworkPolicy enforcement**
  The AWS VPC CNI add-on is configured with `enableNetworkPolicy = "true"` so the application `NetworkPolicy` is actually enforced. Without this, EKS would silently ignore NetworkPolicies.

- **ingress-nginx instead of the AWS Load Balancer Controller (for now)**
  The application is exposed through the `ingress-nginx` controller, which provisions an AWS load balancer for its Service. This avoids the extra IRSA + controller setup that the AWS Load Balancer Controller (ALB + IRSA) would require; moving to it is a natural next iteration.

- **Image pulls without IRSA**
  The managed node group's IAM role carries `AmazonEC2ContainerRegistryReadOnly`, so pods pull from ECR without per-pod IAM roles. IRSA is kept available (the cluster OIDC provider exists) for workloads that genuinely need scoped AWS access later.

- **Keyless CI/CD with OIDC and EKS Access Entries**
  GitHub Actions assumes an IAM role through OIDC instead of using long-lived access keys. That role is granted `kubectl` access through a native EKS **Access Entry** (cluster-admin), not the legacy `aws-auth` ConfigMap.

- **Baseline runtime hardening**
  The Deployment runs as non-root, disables privilege escalation, drops Linux capabilities, and uses Pod Security Admission in `restricted` mode.

- **Restrictive network posture**
  The application `NetworkPolicy` allows ingress only from the `ingress-nginx` and `monitoring` namespaces on the application port, and denies all egress because the current API does not require outbound network access.

- **Availability controls**
  The project includes an HPA for CPU-based scaling and a PDB to avoid all replicas being voluntarily disrupted at once. Because EKS does not bundle `metrics-server`, the deploy installs it as a cluster add-on so the HPA can read pod CPU.

- **No unnecessary platform features**
  GitOps controllers, certificate automation, databases, and tracing were intentionally left out to keep the repository focused and technically consistent.

## Repository Structure

```text
app/                FastAPI application and Dockerfile
infra/              Terraform root and modules (network, registry, eks, github-oidc)
k8s/                Raw Kubernetes manifests
.github/workflows/  Validation and deployment pipelines
docs/               Architecture diagram and project screenshots
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
- `registry` — an ECR repository with immutable tags, scan-on-push, and KMS encryption.
- `eks` — an EKS cluster with a private managed node group, VPC CNI NetworkPolicy enforcement, and control plane logs to CloudWatch (wraps `terraform-aws-modules/eks/aws`).
- `github-oidc` — the GitHub OIDC provider and a least-privilege IAM role for CI/CD.

The composition happens in [infra/main.tf](infra/main.tf). After the modules, two EKS Access Entry resources grant the GitHub Actions role cluster-admin so the CI/CD pipeline can manage workloads.

### Kubernetes

Raw manifests live in [k8s/](k8s): namespace, deployment, service, ingress, hpa, networkpolicy, pdb, and the monitoring stack (Prometheus, Alertmanager, Grafana). The Deployment image points to the project's ECR repository.

### CI/CD

#### Validation Workflow

[.github/workflows/validate.yml](.github/workflows/validate.yml) runs `ruff`, `pytest`, `bandit`, `pip-audit`, `terraform fmt`, `terraform validate`, `checkov`, and `kubeconform`.

#### Deploy Workflow

[.github/workflows/deploy.yml](.github/workflows/deploy.yml) authenticates to AWS via OIDC, then builds, scans (Trivy), and pushes the image to ECR, ensures `ingress-nginx` and `metrics-server` exist, applies the manifests to EKS, sets the Deployment image to the validated commit SHA, and runs a post-deploy smoke test against `/health` and `/quote`. It can also be triggered manually via `workflow_dispatch`.

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
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.8.1/components.yaml
kubectl rollout status -n kube-system deployment/metrics-server --timeout=120s
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

> Delete the `ingress-nginx` Service first (`kubectl delete svc ingress-nginx-controller -n ingress-nginx`) so its AWS load balancer is removed and Terraform can delete the VPC cleanly.

## Limitations & Next Steps

Deliberate scope cuts for a coherent demo, and what the next iteration would add:

- **TLS and DNS** — the Ingress omits host and TLS so the demo works directly through the load balancer hostname. Next: a real domain, `cert-manager` with Let's Encrypt, and host-based routing.
- **AWS Load Balancer Controller** — `ingress-nginx` provisions a classic ELB today. Next: native ALB integration via the AWS Load Balancer Controller with IRSA.
- **Single NAT gateway** — a cost optimization for a demo environment; production would run one NAT gateway per AZ for full high availability.
- **Push-based deploys** — CI applies manifests with `kubectl`. Next: pull-based GitOps reconciliation with Argo CD or Flux.
- **Monitoring durability** — Prometheus stores data in an `emptyDir` with 6h retention and there is no `kube-state-metrics`. Production would add persistent storage and richer cluster-level metrics.
- **Raw manifests** — transparent for review, but Helm or Kustomize overlays would be the natural step for multi-environment deploys.

## Full Run Gallery

Every screenshot below documents a single end-to-end AWS run of the project before the cloud resources were destroyed to control cost.

<details>
<summary><b>Infrastructure — EKS, node group, VPC, load balancer</b></summary>

![EKS cluster overview](docs/screenshots/infra-eks-cluster-overview.png)
The EKS cluster is `Active` on Kubernetes 1.31 with a healthy control plane and zero health issues.

![Managed node group](docs/screenshots/infra-eks-node-group.png)
The managed node group runs 2× `t3.medium` on Amazon Linux 2023 with autoscaling configured between 2 and 4 nodes.

![VPC resource map](docs/screenshots/infra-vpc-resource-map.png)
The VPC spans two Availability Zones with public and private subnets and a NAT gateway for private egress.

![Ingress load balancer](docs/screenshots/infra-ingress-load-balancer.png)
The internet-facing ELB provisioned by `ingress-nginx` is the public entry point to the application.

</details>

<details>
<summary><b>Security &amp; Identity — keyless CI/CD with OIDC</b></summary>

![IAM OIDC identity providers](docs/screenshots/iam-oidc-identity-providers.png)
Two OpenID Connect providers: GitHub Actions (`token.actions.githubusercontent.com`) and the EKS cluster (for IRSA).

![GitHub Actions role trust policy](docs/screenshots/iam-github-actions-role-trust.png)
The deploy role is assumed via `sts:AssumeRoleWithWebIdentity`, scoped by the `sub` claim to this repository only — no static keys.

![GitHub Actions role permissions](docs/screenshots/iam-github-actions-role-permissions.png)
The role carries a single least-privilege inline policy (ECR push to the app repo + `eks:DescribeCluster`).

</details>

<details>
<summary><b>CI/CD — Validate and Deploy workflows</b></summary>

![GitHub Actions workflows](docs/screenshots/ci-actions-workflows.png)
The Validate and Deploy workflows in GitHub Actions.

![Validate workflow](docs/screenshots/ci-validate-workflow.png)
Validation runs application checks, Terraform `fmt`/`validate`, Checkov IaC security, and Kubernetes manifest schema validation.

![Deploy workflow](docs/screenshots/ci-deploy-workflow.png)
Deployment builds and Trivy-scans the image, pushes it to ECR, rolls it out to EKS, and runs a post-deploy smoke test.

</details>

<details>
<summary><b>Container Registry — ECR</b></summary>

![ECR images](docs/screenshots/ecr-images.png)
Images are tagged with the validated commit SHA (immutable tags, KMS-encrypted) and pulled by EKS.

</details>

<details>
<summary><b>Application — served through the ingress</b></summary>

![Swagger UI](docs/screenshots/app-swagger-ui.png)
The Swagger UI is reachable through the Kubernetes ingress.

![Health endpoint](docs/screenshots/app-health.png)
The `/health` endpoint used by Kubernetes probes and the post-deploy smoke test.

![Quote endpoint](docs/screenshots/app-quote-btc.png)
The `/quote` endpoint returning a synthetic market quote for a supported symbol.

![Unsupported symbol](docs/screenshots/app-quote-unsupported-symbol.png)
An unsupported symbol returns a controlled `400` with the list of supported symbols.

</details>

<details>
<summary><b>Observability — Grafana, Prometheus, CloudWatch</b></summary>

![Grafana dashboard](docs/screenshots/obs-grafana-dashboard.png)
The Market Quote API dashboard shows live request rate, p95 latency, and status-code metrics.

![Prometheus targets](docs/screenshots/obs-prometheus-targets.png)
Prometheus scrapes the application metrics endpoint successfully (target `UP`).

![Prometheus request graph](docs/screenshots/obs-prometheus-request-rate.png)
Request rate broken down by handler and status code in the Prometheus expression browser.

![CloudWatch control plane logs](docs/screenshots/obs-cloudwatch-control-plane-logs.png)
The EKS control plane ships `api`, `audit`, and `authenticator` logs to CloudWatch.

</details>

<details>
<summary><b>Alerting — Prometheus rules and Alertmanager</b></summary>

![Prometheus alert firing](docs/screenshots/alert-prometheus-firing.png)
Scaling the app to zero fires the `MarketQuoteApiDown` alerting rule (`FIRING`).

![Alertmanager active alert](docs/screenshots/alert-alertmanager-active.png)
Alertmanager receives and groups the critical alert under its email receiver.

</details>

<details>
<summary><b>Kubernetes — kubectl views of the running cluster</b></summary>

![kubectl get nodes](docs/screenshots/k8s-get-nodes.png)
Two worker nodes `Ready` on EKS 1.31.

![kubectl get all (application)](docs/screenshots/k8s-app-resources.png)
All application resources in one view: pods, Service, Deployment, ReplicaSets, and the HPA.

![kubectl top nodes](docs/screenshots/k8s-top-nodes.png)
Live node CPU/memory usage, served by `metrics-server`.

![kubectl top pods](docs/screenshots/k8s-top-pods.png)
Per-pod resource usage for the application workload.

![App ingress, PDB and NetworkPolicy](docs/screenshots/k8s-ingress-pdb-networkpolicy.png)
The application Ingress, PodDisruptionBudget, and NetworkPolicy.

![Monitoring namespace](docs/screenshots/k8s-monitoring-resources.png)
Prometheus, Grafana, and Alertmanager running in the `monitoring` namespace.

</details>

## Author

**Alexandre Vidal**
Email: alexvidaldepalol@gmail.com
[LinkedIn](https://www.linkedin.com/in/alexvidi/)
[GitHub](https://github.com/alexvidi)
