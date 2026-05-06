# 🚗 Car Prices Tracker

Project created out of curiosity to check if prices for cars manufactured in specific year are getting lower with time or the inflation/quality keep the price high.

It became a full-stack cloud application built on AWS to automatically collect, store, and visualize car prices over time. The entire infrastructure is managed as Code (IaC) using **Terraform** and features automated CI/CD pipelines via **GitHub Actions**.
<br><br><br>
<p align="center">
(click to enlarge)
</p>

<p align="center">
<img width="480" height="270" alt="gif-slow" src="https://github.com/user-attachments/assets/5597b913-358f-4a64-b0ae-7e141be6277c" />
</p>

## 🏗️ Architecture Overview

The system is divided into three main logcal components:

1. **Data Collection (Event-Driven)**: An AWS EventBridge cron job triggers a Python Lambda function daily. It scrapes real-time car prices from external sources and stores the calculated averages in an Amazon DynamoDB table.
2. **Notification Pipeline (Pipes & Filters)**: Using Lambda Destinations, successful data collection events are pushed to an SNS Topic, formatted by a dedicated Python Lambda, and sent to subscribers via Email using a second SNS Topic.
3. **Web Server & API**: An EC2 instance running Apache and a Node.js/Express application visualizes the data using `Chart.js`. The API is exposed via Amazon API Gateway and secured using Amazon Cognito (OAuth2/Hosted UI).


<br><br>
<p align="center">
<img width="1763" height="1269" alt="aws architecture" src="https://github.com/user-attachments/assets/5573ae41-ce25-48d3-ad8a-12930c3cec5a" />
</p>
<br>

## 🔄 Automated Workflows (CI/CD)

The project includes two main GitHub Action workflows that automatically sync your local code with AWS:

* **Lambda Update**: Monitors `src/lambdas/` and updates the corresponding function code on AWS only if the specific file was modified.
* **Web Server Update**: Monitors `src/express/`, copies new files to EC2 via SCP, injects dynamic environment variables (Cognito Domain, API URLs), and restarts the PM2 process.

Both workflows use defensive checks to ensure they only run if the necessary infrastructure (OIDC role/Secrets) has been provisioned by Terraform.

## ✨ Key Features
* **100% Infrastructure as Code**: Fully modularized Terraform setup with conditional resource creation.
* **Zero-Downtime Deployments**: CI/CD pipelines automatically build, zip, and deploy new Lambda & Express.js code without manual intervention.
* **Secure Authentication**: Public API endpoints protected by AWS Cognito User Pools.
* **Serverless Notifications**: Decoupled email notification system utilizing Lambda Destinations and SNS.
* **Dynamic Configuration**: Features can be toggled on/off simply by editing the `.tfvars` file.

## 🛠️ Tech Stack
* **Cloud Provider**: AWS (EC2, Lambda, DynamoDB, API Gateway, Cognito, SNS, EventBridge, IAM, VPC)
* **Infrastructure as Code**: Terraform
* **CI/CD**: GitHub Actions (OIDC Authentication)
* **Backend**: Python 3.14 (Lambdas, BeautifulSoup, Pandas), Node.js / Express (API & Chart generation)
* **Frontend**: HTML, Chart.js (Data Visualization)

---

## 🚀 Setup & Deployment

### 1. Prerequisites
* [Terraform](https://www.terraform.io/downloads.html) installed locally.
* An AWS Account and configured AWS CLI (`aws configure`).
* **GitHub Personal Access Token (PAT)** with `repo` scope, set as an environment variable: `export GITHUB_TOKEN=your_token_here` (required only for CI/CD - if `enable_github_secrets` is set to `true`).

### 2. Infrastructure Configuration - OPTIONAL
To customize the deployment, create a `terraform/terraform.tfvars` file based on your preferences:

```hcl
project_name = "car-prices"

# 1. Enable GitHub Actions CI/CD (Requires OIDC setup)
enable_github_secrets = true
github_owner          = "your-github-username"
github_repository     = "your-repo-name"

# 2. Enable Daily Data Collection
enable_data_collector = true
collector_urls        = "https://url1.com,https://url2.com,https://url3.com"

# 3. Enable Email Notifications (Leave empty to disable)
subscriber_email      = "your.email@example.com"
```

### 3. Deploy to AWS

Run the following commands to provision your cloud environment:

```bash
cd terraform
terraform init
terraform apply
```

*Note: If you enabled notifications, check your email to confirm the AWS SNS subscription.*



## 🧹 Cleanup

To remove all resources and stop AWS charges:
```bash
terraform destroy
```




