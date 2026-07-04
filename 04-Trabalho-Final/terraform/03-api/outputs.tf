output "api_url" {
  description = "Endpoint base da API. Consulte GET {api_url}/faturamento."
  value       = aws_apigatewayv2_api.api.api_endpoint
}
