data "aws_caller_identity" "current" {}

locals {
  lab_role_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
  bucket_name      = "pedeja-datalake-${data.aws_caller_identity.current.account_id}"
  powertools_layer = "arn:aws:lambda:us-east-1:017000801446:layer:AWSLambdaPowertoolsPythonV3-python312-x86_64:25"
}

# Cada fase e autossuficiente: cria seu proprio data lake.
resource "aws_s3_bucket" "datalake" {
  bucket        = local.bucket_name
  force_destroy = true
}

# ---------------------------------------------------------------------------
# Kinesis Data Stream: o dado fica RETIDO (24h padrao) e pode ser lido por
# varios consumidores independentes e reprocessado (replay). Modo on-demand
# para nao gerenciar shards manualmente.
# ---------------------------------------------------------------------------
resource "aws_kinesis_stream" "pedidos" {
  name = "pedeja-pedidos-stream"
  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }
}

# ---------------------------------------------------------------------------
# Produtor: API GW -> publica no stream
# ---------------------------------------------------------------------------
data "archive_file" "produtor_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda-produtor"
  output_path = "${path.module}/build/produtor.zip"
}

resource "aws_lambda_function" "produtor" {
  function_name    = "pedeja-produtor-stream"
  role             = local.lab_role_arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.produtor_zip.output_path
  source_code_hash = data.archive_file.produtor_zip.output_base64sha256
  timeout          = 15
  memory_size      = 128
  layers           = [local.powertools_layer]
  tracing_config { mode = "Active" }
  environment {
    variables = {
      STREAM_NAME                  = aws_kinesis_stream.pedidos.name
      POWERTOOLS_SERVICE_NAME      = "pedeja-produtor-stream"
      POWERTOOLS_METRICS_NAMESPACE = "PedeJa"
      POWERTOOLS_LOG_LEVEL         = "INFO"
    }
  }
}

# ---------------------------------------------------------------------------
# Consumidor 1: Kinesis FIREHOSE -> converte para PARQUET -> S3 (Near Real Time)
# Em vez de uma Lambda gravando arquivo por evento (anti-padrao small-files),
# o Firehose acumula um micro-lote (60s ou 64 MB), converte para Parquet usando
# o schema da tabela Glue, e grava 1 arquivo colunar pronto para o Athena.
# ---------------------------------------------------------------------------

# Catalogo: database + tabela que descrevem o schema dos pedidos. O Firehose usa
# essa tabela para saber como converter o JSON em Parquet; o Athena usa para ler.
resource "aws_glue_catalog_database" "pedeja" {
  name = "pedeja"
}

# Workgroup do Athena com o local de resultados JA configurado. Sem isso, o
# Athena exige que o aluno configure manualmente um "query result location"
# no console antes da primeira consulta. Com o workgroup pronto, basta
# seleciona-lo e consultar.
resource "aws_athena_workgroup" "pedeja" {
  name          = "pedeja"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    result_configuration {
      output_location = "s3://${aws_s3_bucket.datalake.bucket}/athena-results/"
    }
  }
}

resource "aws_glue_catalog_table" "pedidos" {
  name          = "pedidos"
  database_name = aws_glue_catalog_database.pedeja.name
  table_type    = "EXTERNAL_TABLE"
  parameters    = { classification = "parquet" }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.datalake.bucket}/pedidos/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }
    columns {
      name = "pedido_id"
      type = "string"
    }
    columns {
      name = "cliente"
      type = "string"
    }
    columns {
      name = "restaurante"
      type = "string"
    }
    columns {
      name = "item"
      type = "string"
    }
    columns {
      name = "valor"
      type = "double"
    }
    columns {
      name = "cidade"
      type = "string"
    }
    columns {
      name = "event_time"
      type = "string"
    }
  }
}

# Firehose le do Kinesis Data Stream e entrega Parquet no S3.
resource "aws_kinesis_firehose_delivery_stream" "datalake" {
  name        = "pedeja-firehose-datalake"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.pedidos.arn
    role_arn           = local.lab_role_arn
  }

  extended_s3_configuration {
    role_arn            = local.lab_role_arn
    bucket_arn          = "arn:aws:s3:::${aws_s3_bucket.datalake.bucket}"
    prefix              = "pedidos/"
    error_output_prefix = "erros/"

    # Buffer: entrega a cada 60s (Near Real Time) ou 64 MB, o que vier antes.
    buffering_interval = 60
    buffering_size     = 64

    # Converte o JSON recebido em Parquet usando o schema da tabela Glue.
    data_format_conversion_configuration {
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {}
        }
      }
      output_format_configuration {
        serializer {
          parquet_ser_de {}
        }
      }
      schema_configuration {
        role_arn      = local.lab_role_arn
        database_name = aws_glue_catalog_database.pedeja.name
        table_name    = aws_glue_catalog_table.pedidos.name
        region        = "us-east-1"
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Consumidor 2: faturamento em tempo real (agrega, nao grava no S3)
# ---------------------------------------------------------------------------
data "archive_file" "faturamento_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda-faturamento"
  output_path = "${path.module}/build/faturamento.zip"
}

resource "aws_lambda_function" "faturamento" {
  function_name    = "pedeja-faturamento"
  role             = local.lab_role_arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.faturamento_zip.output_path
  source_code_hash = data.archive_file.faturamento_zip.output_base64sha256
  timeout          = 60
  memory_size      = 128
  layers           = [local.powertools_layer]
  tracing_config { mode = "Active" }
  environment {
    variables = {
      POWERTOOLS_SERVICE_NAME      = "pedeja-faturamento"
      POWERTOOLS_METRICS_NAMESPACE = "PedeJa"
      POWERTOOLS_LOG_LEVEL         = "INFO"
    }
  }
}

# ---------------------------------------------------------------------------
# Os DOIS consumidores leem o MESMO stream, de forma independente:
#  - Consumidor A = Firehose (acima), que tem sua propria leitura do stream.
#  - Consumidor B = Lambda faturamento, via event source mapping abaixo.
# starting_position = TRIM_HORIZON: le desde o inicio do stream, entao todo
# aluno processa os mesmos registros retidos (resultado deterministico).
# ---------------------------------------------------------------------------
resource "aws_lambda_event_source_mapping" "stream_to_faturamento" {
  event_source_arn  = aws_kinesis_stream.pedidos.arn
  function_name     = aws_lambda_function.faturamento.arn
  starting_position = "TRIM_HORIZON"
  batch_size        = 500
}

# ---------------------------------------------------------------------------
# API Gateway -> produtor
# ---------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "api" {
  name          = "pedeja-api-fase3"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.produtor.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_pedidos" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /pedidos"
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
  function_name = aws_lambda_function.produtor.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# ---------------------------------------------------------------------------
# Dashboard Fase 3: o mesmo stream alimentando 2 consumidores + negocio
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "fase3" {
  dashboard_name = "PedeJa-Fase3-Streaming"
  dashboard_body = jsonencode({
    widgets = [
      {
        type       = "text", x = 0, y = 0, width = 24, height = 2,
        properties = { markdown = "# PedeJa - Fase 3 (Kinesis: 1 stream -> N consumidores)\nO **mesmo** stream alimenta dois consumidores: o **Firehose** (converte em Parquet -> S3, lido pelo Athena) e a **Lambda de faturamento** (metrica em tempo real). O dado fica retido -> permite **replay**. Isso a fila SQS nao faz." }
      },
      {
        type = "metric", x = 0, y = 2, width = 12, height = 6,
        properties = {
          title  = "Trafego - publicados (stream) vs entregue em Parquet (Firehose)",
          region = "us-east-1",
          metrics = [
            ["PedeJa", "pedidos_publicados", "service", "pedeja-produtor-stream", { stat = "Sum", label = "publicados (5000)" }],
            ["AWS/Firehose", "DeliveryToS3.Records", "DeliveryStreamName", aws_kinesis_firehose_delivery_stream.datalake.name, { stat = "Sum", label = "entregue ao S3 (Parquet)" }]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 2, width = 12, height = 6,
        properties = {
          title  = "Firehose - idade do dado no buffer (s) e faturamento (Lambda)",
          region = "us-east-1",
          metrics = [
            ["AWS/Firehose", "DeliveryToS3.DataFreshness", "DeliveryStreamName", aws_kinesis_firehose_delivery_stream.datalake.name, { stat = "Maximum", label = "data freshness (s)" }],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.faturamento.function_name, { stat = "Average", label = "faturamento (ms)" }]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 8, width = 24, height = 6,
        properties = {
          title  = "Negocio - faturamento em tempo real por cidade",
          region = "us-east-1",
          view   = "timeSeries",
          metrics = [
            ["PedeJa", "faturamento_tempo_real", "service", "pedeja-faturamento", "cidade", "Sao Paulo", { stat = "Sum" }],
            ["...", "cidade", "Rio de Janeiro", { stat = "Sum" }],
            ["...", "cidade", "Curitiba", { stat = "Sum" }],
            ["...", "cidade", "Belo Horizonte", { stat = "Sum" }]
          ]
        }
      }
    ]
  })
}
