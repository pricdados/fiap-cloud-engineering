data "aws_caller_identity" "current" {}

locals {
  lab_role_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
  bucket_name      = "pedeja-datalake-${data.aws_caller_identity.current.account_id}"
  powertools_layer = "arn:aws:lambda:us-east-1:017000801446:layer:AWSLambdaPowertoolsPythonV3-python312-arm64:25"
}

data "archive_file" "api_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/api"
  output_path = "${path.module}/build/api.zip"
}

# ---------------------------------------------------------------------------
# Lambda da API: le o resumo/faturamento.json do S3 e responde em JSON.
# Tambem em Graviton (arm64) — coerente com a Lambda de processamento.
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "api" {
  function_name    = "pedeja-api-faturamento"
  role             = local.lab_role_arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.api_zip.output_path
  source_code_hash = data.archive_file.api_zip.output_base64sha256
  timeout          = 15
  memory_size      = 128
  architectures    = ["arm64"]
  layers           = [local.powertools_layer]

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      BUCKET_DATA_LAKE             = local.bucket_name
      POWERTOOLS_SERVICE_NAME      = "pedeja-api"
      POWERTOOLS_METRICS_NAMESPACE = "PedeJaTF"
      POWERTOOLS_LOG_LEVEL         = "INFO"
    }
  }
}

# ---------------------------------------------------------------------------
# API Gateway HTTP: entrega a requisicao GET /faturamento como EVENTO a Lambda.
# Mesmo padrao AWS_PROXY da demo de Lambda (03.3, fase 1).
# ---------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "api" {
  name          = "pedeja-api-tf"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_faturamento" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /faturamento"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
