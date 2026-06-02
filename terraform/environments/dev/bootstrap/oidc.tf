# 1. Pobieramy odcisk palca (thumbprint) certyfikatu GitHuba
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

# 2. Tworzymy dostawcę tożsamości OIDC w AWS
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# 3. Tworzymy Rolę IAM, którą GitHub będzie mógł przyjąć
resource "aws_iam_role" "github_actions_role" {
  name = "${var.project_name}-github-oidc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # ZABEZPIECZENIE: Tylko Twoje konkretne repozytorium na GitHubie może użyć tej roli!
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_owner}/${var.github_repository}:*"
        }
      }
    }]
  })
}

# Nazwa GitHub Environment pokrywa się z tagiem Environment (prod/dev),
# dzięki czemu bootstrap dev i prod różnią się wyłącznie wartością tfvars.
locals {
  github_environment = var.common_tags["Environment"]
}

# 4. GitHub Environment dla tego konta (izoluje sekrety/zmienne dev vs prod)
resource "github_repository_environment" "this" {
  count       = var.enable_github_secrets ? 1 : 0
  repository  = var.github_repository
  environment = local.github_environment
}

# 5. ARN roli OIDC jako sekret w GitHub Environment
resource "github_actions_environment_secret" "aws_oidc_role_arn" {
  count = var.enable_github_secrets ? 1 : 0

  repository      = var.github_repository
  environment     = github_repository_environment.this[0].environment
  secret_name     = "AWS_OIDC_ROLE_ARN"
  plaintext_value = aws_iam_role.github_actions_role.arn
}

# 6. Token GitHub jako sekret w GitHub Environment (używany przez terraform.yml)
resource "github_actions_environment_secret" "github_token" {
  count = (var.enable_github_secrets && var.github_token != null) ? 1 : 0

  repository      = var.github_repository
  environment     = github_repository_environment.this[0].environment
  secret_name     = "GH_PAT"
  plaintext_value = var.github_token
}

# 7. Backend state — nazwy z bootstrap (suffix losowy), na wypadek przyszłego CI dla dev
resource "github_actions_environment_variable" "tf_state_bucket" {
  count = var.enable_github_secrets ? 1 : 0

  repository    = var.github_repository
  environment   = github_repository_environment.this[0].environment
  variable_name = "TF_STATE_BUCKET"
  value         = aws_s3_bucket.terraform_state.bucket
}

resource "github_actions_environment_variable" "tf_state_dynamodb_table" {
  count = var.enable_github_secrets ? 1 : 0

  repository    = var.github_repository
  environment   = github_repository_environment.this[0].environment
  variable_name = "TF_STATE_DYNAMODB_TABLE"
  value         = aws_dynamodb_table.terraform_locks.name
}

resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
