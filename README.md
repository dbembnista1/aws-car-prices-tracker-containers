# 🚗 Car Prices Tracker - containerized

Project created out of curiosity to check if prices for cars manufactured in specific year are getting lower with time or the inflation/quality keep the price high.

This repository is an **evolution of the original [aws-car-prices-tracker](https://github.com/dbembnista1/aws-car-prices-tracker)** project. The core application logic (scraping, API, charts) stays the same — the focus here is on cloud engineering improvements: containerized web on **ECS Fargate** (replacing EC2 and also introducing CloudFront and ALB), **CPU-based ECS autoscaling**, CI/CD including Terraform code changes (triggered on PR), remote Terraform state, and **dev/prod** separation using separate AWS accounts, state files and folder structure.


## 🏗️ Architecture Overview

The system is divided into three main logical components:

1. **Data Collection (Event-Driven)**: An AWS EventBridge cron job triggers a Python Lambda function daily at 08:00 CET. It scrapes car prices from external sources, stores calculated averages in Amazon DynamoDB, and — on success — publishes the result to SNS via Lambda Destinations.
2. **Notification Pipeline (Pipes & Filters)**: The raw SNS topic triggers a formatting Lambda, which prepares the message and publishes it to a second SNS topic that delivers email notifications to subscribers.
3. **Web Application & API**: Users reach a Node.js/Express container running on **ECS Fargate** behind CloudFront and an Application Load Balancer. **Application Auto Scaling** keeps 2–4 tasks running (CPU target 70%) for HA across AZs; after deploy, task count is managed by autoscaling, not Terraform. The homepage reads price history directly from DynamoDB; authenticated API calls go through **API Gateway** (two Lambda functions) secured with **Amazon Cognito** (OAuth2 / Hosted UI). Container images are stored in **ECR** and deployed via GitHub Actions.

<p align="center">
  <img src="architecture%20diagram.png" alt="AWS architecture diagram" width="100%" />
</p>

## 🔄 Automated Workflows (CI/CD)

The project includes three GitHub Actions workflows that sync code and infrastructure with AWS:

* **Terraform CI/CD** (`terraform.yml`): On every PR to `main` — `fmt`, `validate`, and `plan` (with results posted as a PR comment). On merge to `main` — automatic `terraform apply` for the **prod** environment. Dev infrastructure is applied locally (see Setup below).
* **Lambda CI/CD** (`update-lambdas.yml`): Checks Python code for syntax errors on PR; deploys changed Lambda functions to **prod** after merge to `main`.
* **App CI/CD** (`deploy-app.yml`): Builds the Docker image and pushes it to **ECR** on PR/push. Rolls out a new ECS deployment on merge to `main` (prod) or via manual `workflow_dispatch` (dev or prod).

All workflows authenticate to AWS via **OIDC** — no long-lived access keys in GitHub Secrets. Bootstrap resources (S3 state bucket, DynamoDB lock table, OIDC IAM role) live outside the main stack and survive `terraform destroy`, so CI/CD can always rebuild the environment.

## ✨ Key Features
* **100% Infrastructure as Code**: Fully modularized Terraform setup with conditional resource creation.
* **Containerized Web Tier**: Express.js runs as a Docker container on ECS Fargate — no EC2 management, no SSH/SCP deploys.
* **ECS Auto Scaling**: CPU target tracking (70%) with min 2 / max 4 Fargate tasks; Terraform sets the initial count and then ignores `desired_count` so scaling is driven by load.
* **Zero-Downtime Deployments**: CI/CD pipelines automatically build, zip, and deploy Lambda code and container images without manual intervention.
* **Secure Authentication**: API endpoints protected by AWS Cognito User Pools.
* **Serverless Notifications**: Decoupled email notification system utilizing Lambda Destinations and SNS.
* **Dev/Prod Isolation**: Separate AWS accounts, separate Terraform state, and GitHub Environments (`dev` / `prod`) with per-account OIDC roles.
* **Dynamic Configuration**: Features such as the data collector and email notifications can be toggled on/off via `.tfvars`.

## 🛠️ Tech Stack
* **Cloud Provider**: AWS (ECS Fargate, Application Auto Scaling, ECR, ALB, CloudFront, Lambda, DynamoDB, API Gateway, Cognito, SNS, EventBridge, IAM, VPC, S3)
* **Infrastructure as Code**: Terraform (remote state on S3 + DynamoDB locking)
* **CI/CD**: GitHub Actions (OIDC authentication)
* **Backend**: Python 3.14 (Lambdas, BeautifulSoup, Pandas), Node.js / Express (charts & API client)
* **Frontend**: HTML, Chart.js (data visualization)
* **Containers**: Docker

---

## 🚀 Setup & Deployment

Dev and prod run in **separate AWS accounts** with isolated Terraform state. Each environment follows the same three phases: **bootstrap** (once per account) → **configure** → **deploy**.

### Repository layout (dev / prod separation)

```
terraform/
├── modules/                         # Shared IaC — identical for dev and prod
│   ├── network/
│   ├── ecs/
│   ├── api/
│   └── ...
│
└── environments/
    ├── dev/                         # AWS account: dev  |  AWS CLI profile: dev  |  GitHub Environment: dev
    │   ├── bootstrap/               
    │   │   └── terraform.tfvars.example
    │   ├── main.tf                
    │   ├── terraform.tfvars.example
    │   └── backend.conf           
    │
    └── prod/                        # AWS account: prod  |  AWS CLI profile: prod  |  GitHub Environment: prod
        ├── bootstrap/
        │   └── terraform.tfvars.example
        ├── main.tf
        ├── terraform.tfvars.example
        └── backend.conf

scripts/
├── deploy-dev.ps1 / deploy-dev.sh       # Dev deploy scripts
├── deploy-prod.ps1 / deploy-prod.sh     # Prod deploy scripts
└── test-ecs-autoscaling.ps1             # Verify scaling config; optional ALB load test
```

No shared state bucket or cross-account access — each side has its own bootstrap, backend, and AWS account.

### Get your own copy

Bootstrap configures OIDC trust for a **specific GitHub repository**. To deploy under your own AWS accounts, run the project from **your** repo (one repo shared by dev and prod — separation is by AWS account, not by repository).

**1. Create an empty repository on GitHub** (no README, no `.gitignore` — avoid merge conflicts).

**2. Clone this project and push it to your remote:**

```bash
git clone https://github.com/dbembnista1/project1-car-prices-terraform-containers.git
cd project1-car-prices-terraform-containers
git remote set-url origin https://github.com/YOUR_USER/YOUR_REPO.git
git push -u origin main
```

Alternatively: **Fork** this repository on GitHub and clone your fork.


### Prerequisites
* [Terraform](https://www.terraform.io/downloads.html), [AWS CLI](https://aws.amazon.com/cli/), and [GitHub CLI](https://cli.github.com/) (`gh`)
* A **GitHub PAT** with `repo` scope (passed as `TF_VAR_github_token`, never committed)

---

### Dev environment

Local-only infrastructure — Terraform is **not** applied by GitHub Actions for dev.

**1. AWS credentials**

```bash
aws configure --profile dev
```

**2. Bootstrap**

Creates S3 state bucket, DynamoDB lock table, OIDC role, and GitHub Environment `dev`.

```bash
$env:TF_VAR_github_token = "your-gh-token"

cd terraform/environments/dev/bootstrap
cp terraform.tfvars.example terraform.tfvars   # set github_owner, github_repository
terraform init
terraform apply
```

**3. Main stack configuration**

```bash
cd ../
cp terraform.tfvars.example terraform.tfvars   # set github_owner, github_repository; optional features
```

**4. Deploy**

Orchestrates `terraform apply`, builds the Docker image via GitHub Actions (`workflow_dispatch` → dev), and rolls out ECS:

```bash
$env:TF_VAR_github_token = "your-gh-token"

./scripts/deploy-dev.ps1    # Windows
./scripts/deploy-dev.sh     # Linux/macOS
```

The script prints the CloudFront URL when finished.

**5. Ongoing management**

Re-run the deploy script to apply infrastructure changes and roll out the app:

```bash
$env:TF_VAR_github_token = "your-gh-token"

./scripts/deploy-dev.ps1    # Windows
./scripts/deploy-dev.sh     # Linux/macOS
```

---

### Prod environment

**1. AWS credentials**

```bash
aws configure --profile prod
```

**2. Bootstrap**

Creates S3 state bucket, DynamoDB lock table, OIDC role, and GitHub Environment `prod`.

```bash
$env:TF_VAR_github_token = "your-gh-token"

cd terraform/environments/prod/bootstrap
cp terraform.tfvars.example terraform.tfvars   # set github_owner, github_repository
terraform init
terraform apply
```

**3. Main stack configuration**

```bash
cd ../
cp terraform.tfvars.example terraform.tfvars   # set github_owner, github_repository; optional features
```

**4. Deploy**

Orchestrates `terraform apply`, builds the Docker image via GitHub Actions (`workflow_dispatch` → prod), and rolls out ECS:

```bash
$env:TF_VAR_github_token = "your-gh-token"

./scripts/deploy-prod.ps1    # Windows
./scripts/deploy-prod.sh     # Linux/macOS
```

The script prints the CloudFront URL when finished.

**5. Ongoing management**

* Team collaboration (CI/CD): create a branch → open a PR to `main` → `terraform.yml` posts a plan comment → merge triggers `terraform apply` and deploys Lambdas/app when `terraform/**`, `src/lambdas/**`, or `src/express/**` change
* Local deploy:

```bash
$env:TF_VAR_github_token = "your-gh-token"

./scripts/deploy-prod.ps1    # Windows
./scripts/deploy-prod.sh     # Linux/macOS
```


---

### Destroy behaviour

`terraform destroy` on the main stack removes application resources (ECS, DynamoDB, API Gateway, etc.) but **leaves bootstrap intact** (S3, DynamoDB locks, OIDC). After a destroy, prod can be rebuilt via CI/CD on the next merge to `main` (or by running the deploy script again).

## 🧹 Cleanup

### Dev

```powershell
$env:TF_VAR_github_token = "your-gh-token"

# Remove application resources (bootstrap stays)
cd terraform/environments/dev
terraform destroy

# Full teardown including remote state and OIDC (disables CI/CD for dev)
cd bootstrap
terraform destroy
```

### Prod

```powershell
$env:TF_VAR_github_token = "your-gh-token"

# Remove application resources (bootstrap stays)
cd terraform/environments/prod
terraform destroy

# Full teardown including remote state and OIDC (disables CI/CD for prod)
cd bootstrap
terraform destroy
```

