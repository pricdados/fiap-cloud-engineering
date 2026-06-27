output "api_url" {
  description = "Endpoint do API Gateway da Fase 3. O aluno faz POST em {api_url}/pedidos."
  value       = aws_apigatewayv2_api.api.api_endpoint
}

output "stream_name" {
  description = "Nome do Kinesis Data Stream de pedidos."
  value       = aws_kinesis_stream.pedidos.name
}

output "bucket_datalake" {
  description = "Bucket S3 onde os pedidos sao gravados."
  value       = aws_s3_bucket.datalake.bucket
}

output "dashboard_url" {
  description = "Link direto do dashboard de observabilidade da Fase 3."
  value       = "https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards/dashboard/${aws_cloudwatch_dashboard.fase3.dashboard_name}"
}

output "glue_database" {
  description = "Database Glue que o Athena consulta."
  value       = aws_glue_catalog_database.pedeja.name
}

output "athena_workgroup" {
  description = "Workgroup do Athena com o local de resultados ja configurado."
  value       = aws_athena_workgroup.pedeja.name
}

output "athena_results" {
  description = "Prefixo S3 onde o Athena grava os resultados das queries."
  value       = "s3://${aws_s3_bucket.datalake.bucket}/athena-results/"
}
