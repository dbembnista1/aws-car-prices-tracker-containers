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

# 4. Automatyczne wysłanie ARN tej roli jako Sekret do GitHuba
resource "github_actions_secret" "aws_oidc_role_arn" {
  # Opcjonalne: Używamy count, jeśli chcesz by to było przełączane
  count           = var.enable_github_secrets ? 1 : 0
  
  repository      = var.github_repository
  secret_name     = "AWS_OIDC_ROLE_ARN"
  plaintext_value = aws_iam_role.github_actions_role.arn
}

resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess" 
}