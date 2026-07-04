output "bucket_datalake" {
  description = "Nome do bucket S3 do data lake (destino da migracao)."
  value       = aws_s3_bucket.datalake.bucket
}

output "instance_id" {
  description = "ID da EC2 de migracao (use para abrir a sessao SSM)."
  value       = aws_instance.migracao.id
}

output "efs_id" {
  description = "ID do EFS legado onde os pedidos foram plantados."
  value       = aws_efs_file_system.legado.id
}
