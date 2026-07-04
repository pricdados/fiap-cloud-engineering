output "lambda_name" {
  description = "Nome da Lambda de processamento (use para invocar via CLI)."
  value       = aws_lambda_function.processa.function_name
}

output "lambda_arch" {
  description = "Arquitetura da Lambda (confirma que roda em Graviton)."
  value       = aws_lambda_function.processa.architectures
}
