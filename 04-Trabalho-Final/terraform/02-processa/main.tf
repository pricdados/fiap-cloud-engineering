data "aws_caller_identity" "current" {}

locals {
  lab_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
  bucket_name  = "pedeja-datalake-${data.aws_caller_identity.current.account_id}"
  # Layer publica do AWS Lambda Powertools — versao ARM64, porque esta Lambda
  # roda em Graviton (a mesma decisao de arquitetura da demo 03.1).
  powertools_layer = "arn:aws:lambda:us-east-1:017000801446:layer:AWSLambdaPowertoolsPythonV3-python312-arm64:25"
}

# O bucket ja existe (criado no stack 01-storage). So referenciamos.
data "aws_s3_bucket" "datalake" {
  bucket = local.bucket_name
}

data "archive_file" "processa_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/processa"
  output_path = "${path.module}/build/processa.zip"
}

# ---------------------------------------------------------------------------
# Lambda de processamento em GRAVITON (arm64). Le os pedidos crus de raw/,
# agrega o faturamento por cidade e grava o resumo em resumo/faturamento.json.
# A escolha arm64 aplica na pratica a decisao da demo x86 vs Graviton (03.1):
# workload CPU-leve de agregacao, ~20% mais barato, sem perda perceptivel.
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "processa" {
  function_name    = "pedeja-processa-faturamento"
  role             = local.lab_role_arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.processa_zip.output_path
  source_code_hash = data.archive_file.processa_zip.output_base64sha256
  timeout          = 60
  memory_size      = 256
  architectures    = ["arm64"] # <-- Graviton
  layers           = [local.powertools_layer]

  tracing_config {
    mode = "Active" # X-Ray, como na demo de Lambda
  }

  environment {
    variables = {
      BUCKET_DATA_LAKE             = local.bucket_name
      POWERTOOLS_SERVICE_NAME      = "pedeja-processa"
      POWERTOOLS_METRICS_NAMESPACE = "PedeJaTF"
      POWERTOOLS_LOG_LEVEL         = "INFO"
    }
  }
}
