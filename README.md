# 🚗 Car Prices Tracker

Project created out of curiosity to check if prices for cars manufactured in specific year are getting lower with time or the inflation/quality keep the price high.

It became a full-stack cloud application built on AWS to automatically collect, store, and visualize car prices over time. The entire infrastructure is managed as Code (IaC) using **Terraform** and features automated CI/CD pipelines via **GitHub Actions**.

This repository is an **evolution of the original [aws-car-prices-tracker](https://github.com/dbembnista1/aws-car-prices-tracker)** project. The core application logic (scraping, API, charts) stays the same — the focus here is on cloud engineering improvements: containerized web on **ECS Fargate** (replacing EC2), remote Terraform state, OIDC-based CI/CD, and separate **dev/prod** AWS accounts.
<br><br><br>
<p align="center">
(click to enlarge)
</p>

<p align="center">
<img width="480" height="270" alt="gif-slow" src="https://github.com/user-attachments/assets/5597b913-358f-4a64-b0ae-7e141be6277c" />
</p>

## 🏗️ Architecture Overview

The system is divided into three main logical components:

1. **Data Collection (Event-Driven)**: An AWS EventBridge cron job triggers a Python Lambda function daily at 08:00 CET. It scrapes car prices from external sources, stores calculated averages in Amazon DynamoDB, and — on success — publishes the result to SNS via Lambda Destinations.
2. **Notification Pipeline (Pipes & Filters)**: The raw SNS topic triggers a formatting Lambda, which prepares the message and publishes it to a second SNS topic that delivers email notifications to subscribers.
3. **Web Application & API**: Users reach a Node.js/Express container running on **ECS Fargate** behind CloudFront and an Application Load Balancer. The homepage reads price history directly from DynamoDB; authenticated API calls go through **API Gateway** (two Lambda functions) secured with **Amazon Cognito** (OAuth2 / Hosted UI). Container images are stored in **ECR** and deployed via GitHub Actions.

<br><br>
<p align="center">
<img width="1763" height="1269" alt="aws architecture" src="https://github.com/user-attachments/assets/5573ae41-ce25-48d3-ad8a-12930c3cec5a" />
</p>
<br>

## 🔄 Automated Workflows (CI/CD)

The project includes three GitHub Actions workflows that sync code and infrastructure with AWS:

* **Terraform CI/CD** (`terraform.yml`): On every PR to `main` — `fmt`, `validate`, and `plan` (with results posted as a PR comment). On merge to `main` — automatic `terraform apply` for the **prod** environment. Dev infrastructure is applied locally (see Setup below).
* **Lambda CI/CD** (`update-lambdas.yml`): Lints Python code on PR; deploys changed Lambda functions to **prod** after merge to `main`.
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

## 🚀 Setup & Deployment (Admin vs Team Workflow)

This project uses a separated state lifecycle to ensure safe CI/CD deployments and seamless team collaboration.

### 1. Initialization (Admin / DevOps) — do this once per AWS account

The **Bootstrap** phase creates the immutable foundation: S3 bucket for Terraform state, DynamoDB table for state locking, GitHub OIDC IAM role, and GitHub Environment secrets/variables. Bootstrap is applied manually and is never destroyed during normal operations.

**Prerequisites:**
* [Terraform](https://www.terraform.io/downloads.html) installed locally.
* An AWS account with configured AWS CLI (`aws configure --profile dev` or `--profile prod`).
* **GitHub Personal Access Token (PAT)** with `repo` scope: `export TF_VAR_github_token=your_token_here`.

```bash
cd terraform/environments/prod/bootstrap   # or dev/bootstrap
cp terraform.tfvars.example terraform.tfvars   # customize values
terraform init
terraform apply
```

### 2. Infrastructure Configuration (Optional)

Create a `terraform.tfvars` file in the target environment directory (`terraform/environments/prod/` or `terraform/environments/dev/`):

```hcl
project_name = "car-prices"

# 1. Enable GitHub Actions CI/CD (requires bootstrap OIDC setup)
enable_github_secrets = true
github_owner          = "your-github-username"
github_repository     = "your-repo-name"

# 2. Enable Daily Data Collection
enable_data_collector = true
collector_urls        = "https://url1.com,https://url2.com,https://url3.com"

# 3. Enable Email Notifications (leave empty to disable)
subscriber_email      = "your.email@example.com"
```

### 3. Deploy to AWS

**Prod (CI/CD — no local AWS keys needed for day-to-day work):**
1. Create a branch and open a Pull Request.
2. GitHub Actions runs `terraform plan` and posts the result as a PR comment.
3. Merge to `main` — `terraform apply` runs automatically, followed by app and Lambda deploys when relevant paths change.

**Dev (local apply):**
```bash
./scripts/deploy-dev.ps1    # Windows
./scripts/deploy-dev.sh     # Linux/macOS
```

**Prod (full local orchestration — optional):**
```bash
./scripts/deploy-prod.ps1
./scripts/deploy-prod.sh
```

If you run `terraform destroy` on the main infrastructure, it removes all application resources (ECS, DynamoDB, API Gateway, etc.) **except** Bootstrap (S3, DynamoDB locks, OIDC). GitHub Actions retains AWS access and can rebuild everything on the next push to `main`.

## 🧹 Cleanup

To remove all application resources and stop AWS charges (Bootstrap stays intact):
```bash
cd terraform/environments/prod   # or dev
terraform destroy
```

To fully tear down an environment including remote state and OIDC (disables CI/CD for that account):
```bash
cd terraform/environments/prod/bootstrap   # or dev/bootstrap
terraform destroy
```

