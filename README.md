# 🚗 Car Prices Tracker - containerized

Project created out of curiosity to check if prices for cars manufactured in specific year are getting lower with time or the inflation/quality keep the price high.

This repository is an **evolution of the original [aws-car-prices-tracker](https://github.com/dbembnista1/aws-car-prices-tracker)** project. The core application logic (scraping, API, charts) stays the same — the focus here is on cloud engineering improvements: containerized web on **ECS Fargate** (replacing EC2 and also intruducing CloudFront and ALB), CI/CD including Terraform code changes (triggered on PR), remote Terraform state, and **dev/prod** separation using separate AWS accounts, state files and folder structure.


## 🏗️ Architecture Overview

The system is divided into three main logical components:

1. **Data Collection (Event-Driven)**: An AWS EventBridge cron job triggers a Python Lambda function daily at 08:00 CET. It scrapes car prices from external sources, stores calculated averages in Amazon DynamoDB, and — on success — publishes the result to SNS via Lambda Destinations.
2. **Notification Pipeline (Pipes & Filters)**: The raw SNS topic triggers a formatting Lambda, which prepares the message and publishes it to a second SNS topic that delivers email notifications to subscribers.
3. **Web Application & API**: Users reach a Node.js/Express container running on **ECS Fargate** behind CloudFront and an Application Load Balancer. The homepage reads price history directly from DynamoDB; authenticated API calls go through **API Gateway** (two Lambda functions) secured with **Amazon Cognito** (OAuth2 / Hosted UI). Container images are stored in **ECR** and deployed via GitHub Actions.

<br><br>
<p align="center">
<img width="1829" height="1327" alt="aws arch containers drawio" src="https://github.com/user-attachments/assets/7c382a6b-35bc-404f-87c3-548dd0f73431" />
</p>
<br>

## 🔄 Automated Workflows (CI/CD)

The project includes three GitHub Actions workflows that sync code and infrastructure with AWS:

* **Terraform CI/CD** (`terraform.yml`): On every PR to `main` — `fmt`, `validate`, and `plan` (with results posted as a PR comment). On merge to `main` — automatic `terraform apply` for the **prod** environment. Dev infrastructure is applied locally (see Setup below).
* **Lambda CI/CD** (`update-lambdas.yml`): Checks Python code for syntax errors on PR; deploys changed Lambda functions to **prod** after merge to `main`.
* **App CI/CD** (`deploy-app.yml`): Builds the Docker image and pushes it to **ECR** on PR/push. Rolls out a new ECS deployment on merge to `main` (prod) or via manual `workflow_dispatch` (dev or prod).

All workflows authenticate to AWS via **OIDC** — no long-lived access keys in GitHub Secrets. Bootstrap resources (S3 state bucket, DynamoDB lock table, OIDC IAM role) live outside the main stack and survive `terraform destroy`, so CI/CD can always rebuild the environment.

## ✨ Key Features
* **100% Infrastructure as Code**: Fully modularized Terraform setup with conditional resource creation.
* **Containerized Web Tier**: Express.js runs as a Docker container on ECS Fargate — no EC2 management, no SSH/SCP deploys.
* **Zero-Downtime Deployments**: CI/CD pipelines automatically build, zip, and deploy Lambda code and container images without manual intervention.
* **Secure Authentication**: API endpoints protected by AWS Cognito User Pools.
* **Serverless Notifications**: Decoupled email notification system utilizing Lambda Destinations and SNS.
* **Dev/Prod Isolation**: Separate AWS accounts, separate Terraform state, and GitHub Environments (`dev` / `prod`) with per-account OIDC roles.
* **Dynamic Configuration**: Features such as the data collector and email notifications can be toggled on/off via `.tfvars`.

## 🛠️ Tech Stack
* **Cloud Provider**: AWS (ECS Fargate, ECR, ALB, CloudFront, Lambda, DynamoDB, API Gateway, Cognito, SNS, EventBridge, IAM, VPC, S3)
* **Infrastructure as Code**: Terraform (remote state on S3 + DynamoDB locking)
* **CI/CD**: GitHub Actions (OIDC authentication)
* **Backend**: Python 3.14 (Lambdas, BeautifulSoup, Pandas), Node.js / Express (charts & API client)
* **Frontend**: HTML, Chart.js (data visualization)
* **Containers**: Docker

---

## 🚀 Setup & Deployment

Dev and prod run in **separate AWS accounts** with isolated Terraform state. Each environment follows the same three phases: **bootstrap** (once per account) → **configure** → **deploy**.

**Shared prerequisites:**
* [Terraform](https://www.terraform.io/downloads.html), [AWS CLI](https://aws.amazon.com/cli/), and [GitHub CLI](https://cli.github.com/) (`gh`)
* A **GitHub PAT** with `repo` scope (passed as `TF_VAR_github_token`, never committed)

---

### Dev environment (end-to-end)

Local-only infrastructure — Terraform is **not** applied by GitHub Actions for dev.

**1. AWS credentials**

```bash
aws configure --profile dev
```

**2. Bootstrap** (once per dev account)

Creates S3 state bucket, DynamoDB lock table, OIDC role, and GitHub Environment `dev`.

```bash
export TF_VAR_github_token="ghp_..."   # PowerShell: $env:TF_VAR_github_token = "ghp_..."

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
./scripts/deploy-dev.ps1    # Windows
./scripts/deploy-dev.sh     # Linux/macOS
```

The script prints the CloudFront URL when finished.

**5. Day-to-day updates**

* Terraform changes: `cd terraform/environments/dev` → `terraform plan` / `terraform apply`
* App code only: `gh workflow run deploy-app.yml -f environment=dev`

---

### Prod environment (end-to-end)

**1. AWS credentials**

```bash
aws configure --profile prod
```

**2. Bootstrap** (once per prod account)

Creates S3 state bucket, DynamoDB lock table, OIDC role, and GitHub Environment `prod`.

```bash
export TF_VAR_github_token="ghp_..."

cd terraform/environments/prod/bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

**3. Main stack configuration**

```bash
cd ../
cp terraform.tfvars.example terraform.tfvars
```

**4. Deploy**

**Option A — full local deploy** (same flow as dev):

```bash
./scripts/deploy-prod.ps1
./scripts/deploy-prod.sh
```

**Option B — team workflow via GitHub Actions** (recommended for prod):

1. Create a branch and open a Pull Request.
2. `terraform.yml` runs `plan` and posts the result as a PR comment.
3. Merge to `main` — `terraform apply` runs automatically; app and Lambda workflows deploy when relevant paths change.

> Until bootstrap is applied, disable the **Terraform CI/CD** workflow in GitHub Actions to avoid failed runs on merge.

---

### Destroy behaviour

`terraform destroy` on the main stack removes application resources (ECS, DynamoDB, API Gateway, etc.) but **leaves bootstrap intact** (S3, DynamoDB locks, OIDC). GitHub Actions can rebuild prod from the next push to `main`.

## 🧹 Cleanup

### Dev

```bash
# Remove application resources (bootstrap stays)
cd terraform/environments/dev
terraform destroy

# Full teardown including remote state and OIDC (disables CI/CD for dev)
cd bootstrap
terraform destroy
```

### Prod

```bash
# Remove application resources (bootstrap stays)
cd terraform/environments/prod
terraform destroy

# Full teardown including remote state and OIDC (disables CI/CD for prod)
cd bootstrap
terraform destroy
```

