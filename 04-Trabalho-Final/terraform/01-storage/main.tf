data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

# AMI Amazon Linux 2 mais recente (traz o SSM agent pre-instalado -> acesso sem SSH).
data "aws_ssm_parameter" "linux_ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

locals {
  # Data lake unico por conta (account_id evita colisao no namespace global do S3).
  bucket_name = "pedeja-datalake-${data.aws_caller_identity.current.account_id}"
}

# ---------------------------------------------------------------------------
# Rede: VPC propria e autossuficiente (o Trabalho Final nao depende de nenhuma
# demo ter rodado antes). Uma VPC com subnet publica e internet gateway basta.
# ---------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "trabalho-final-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "trabalho-final-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "trabalho-final-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "trabalho-final-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security group: libera NFS (2049) para o mount do EFS. Nao abre porta 22 —
# o acesso a EC2 e via SSM Session Manager (sem SSH), como nas demos.
resource "aws_security_group" "efs" {
  name   = "trabalho-final-efs-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["10.20.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "trabalho-final-efs-sg" }
}

# ---------------------------------------------------------------------------
# Data lake S3: destino da migracao (raw/), do processamento (resumo/) e da API.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "datalake" {
  bucket        = local.bucket_name
  force_destroy = true # permite destroy mesmo com objetos dentro (so para o lab)
}

# ---------------------------------------------------------------------------
# EFS: o "servidor de arquivos legado" da PedeJa. O user-data da EC2 planta os
# 10 pedidos aqui dentro, simulando dados que ja existiam antes da migracao.
# ---------------------------------------------------------------------------
resource "aws_efs_file_system" "legado" {
  performance_mode = "generalPurpose"
  tags             = { Name = "pedeja-efs-legado" }
}

resource "aws_efs_mount_target" "legado" {
  file_system_id  = aws_efs_file_system.legado.id
  subnet_id       = aws_subnet.public.id
  security_groups = [aws_security_group.efs.id]
}

# ---------------------------------------------------------------------------
# EC2: onde o aluno entra via SSM para rodar a migracao EFS -> S3.
# Usa LabInstanceProfile (perfil pre-criado do Academy, da acesso SSM + S3).
# O user-data monta o EFS e planta os pedidos.json dentro dele.
# ---------------------------------------------------------------------------
resource "aws_instance" "migracao" {
  ami                    = data.aws_ssm_parameter.linux_ami.value
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.efs.id]
  iam_instance_profile   = "LabInstanceProfile"
  depends_on             = [aws_efs_mount_target.legado]

  tags = { Name = "pedeja-migracao-instance" }

  # Planta os pedidos no EFS. Cada pedido vira um arquivo .json, como se o
  # sistema legado tivesse gravado um arquivo por pedido no file server.
  user_data = <<-EOF
    #!/bin/bash -xe
    yum update -y
    yum install -y amazon-efs-utils jq
    mkdir -p /efs
    mount -t efs ${aws_efs_file_system.legado.id}:/ /efs
    mkdir -p /efs/pedidos
    cat > /tmp/pedidos.json <<'PEDIDOS'
${file("${path.module}/../../dados/pedidos.json")}
PEDIDOS
    # Explode o array em um arquivo por pedido dentro do EFS (formato do legado).
    jq -c '.[]' /tmp/pedidos.json | while read -r p; do
      id=$(echo "$p" | jq -r '.pedido_id')
      echo "$p" > /efs/pedidos/$id.json
    done
    chown -R ec2-user:ec2-user /efs/pedidos
  EOF
}
