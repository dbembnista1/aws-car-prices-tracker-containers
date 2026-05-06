# Fetch the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}


resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

#public key
resource "aws_key_pair" "deployer_key" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

#private key
resource "local_file" "ssh_key" {
  filename        = "${path.module}/../../${var.project_name}-key.pem"
  content         = tls_private_key.ec2_key.private_key_pem
  file_permission = "0400"
}

# Security Group for the web server
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  vpc_id      = var.vpc_id
  description = "Security group for web server allowing HTTP, HTTPS, and SSH"

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH access for GitHub Actions"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project_name}-sg" })
}

# EC2 Instance
resource "aws_instance" "web_server" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = aws_key_pair.deployer_key.key_name

  user_data = <<-EOF
#!/bin/bash
# 1. Update system and install dependencies
dnf update -y
dnf install -y git nodejs httpd mod_ssl gettext
dnf install -y cairo pango libjpeg-turbo giflib pixman pango-devel cairo-devel
npm install -g pm2

# SSL Setup (Self-signed for HTTPS support)
mkdir -p /etc/ssl/private /etc/ssl/certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/selfsigned.key \
  -out /etc/ssl/certs/selfsigned.crt \
  -subj "/C=PL/ST=State/L=City/O=Organization/CN=localhost"

# Apache Proxy Configuration
cat << 'CONFIG' > /etc/httpd/conf.d/express.conf
<VirtualHost *:80>
    ProxyPreserveHost On
    ProxyPass / http://localhost:3000/
    ProxyPassReverse / http://localhost:3000/
</VirtualHost>

<VirtualHost *:443>
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/private/selfsigned.key
    ProxyPreserveHost On
    ProxyPass / http://localhost:3000/
    ProxyPassReverse / http://localhost:3000/
</VirtualHost>
CONFIG

systemctl enable httpd
systemctl start httpd

# Initial Application Deployment
git clone https://github.com/dbembnista1/project1-car-prices-terraform.git /tmp/car-prices-repo
mkdir -p /var/www/app
cp -r /tmp/car-prices-repo/src/express/* /var/www/app/
rm -rf /tmp/car-prices-repo

#  Inject Variables into HTML Template
export COGNITO_DOMAIN="${var.cognito_domain}"
export COGNITO_CLIENT_ID="${var.cognito_client_id}"
export API_BASE_URL="${var.api_base_url}"
export EC2_HOST="${aws_eip.web_server_eip.public_ip}"

HTML_FILE="/var/www/app/public/api-form-with-authentication-hostedUI.html"
envsubst '$COGNITO_DOMAIN $COGNITO_CLIENT_ID $API_BASE_URL $EC2_HOST' < $HTML_FILE > temp.html && mv temp.html $HTML_FILE

# Install and Start Node.js app
cd /var/www/app
npm install
chown -R ec2-user:ec2-user /var/www/app
sudo -u ec2-user pm2 start app.js --name "car-prices-api"
sudo -u ec2-user pm2 save
EOF

  tags = merge(var.tags, { Name = "${var.project_name}-web-server" })
}

resource "aws_iam_policy" "dynamodb_read_policy" {
  name        = "CarPricesDynamoDBRead"
  description = "Allows EC2 to read from car_prices table"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:GetItem"
        ]
        Effect   = "Allow"
        Resource = var.dynamodb_table_arn # Celujemy konkretnie w Twoją tabelę
      }
    ]
  })
}


resource "aws_iam_role" "ec2_role" {
  name = "car_prices_ec2_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

#Attach dynamodb read policy to role
resource "aws_iam_role_policy_attachment" "attach_dynamo" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.dynamodb_read_policy.arn
}

#instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "car_prices_instance_profile"
  role = aws_iam_role.ec2_role.name
}

# Reserve elastic ip
resource "aws_eip" "web_server_eip" {
  domain = "vpc"
  
  tags = merge(var.tags, { Name = "${var.project_name}-static-ip" })
}

# Attach EIP to instance
resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.web_server.id
  allocation_id = aws_eip.web_server_eip.id
}