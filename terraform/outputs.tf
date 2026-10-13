# Contrato desta stack com `lambda-auth` e `app-oficina`.
#
# Nenhum valor sensível sai em texto claro: o endpoint é marcado como
# sensitive e a senha nunca vira output — quem precisa dela lê o segredo no
# Secrets Manager em tempo de execução.

output "db_endpoint" {
  description = "Endpoint do RDS (host:porta)."
  value       = module.rds.db_instance_endpoint
  sensitive   = true
}

output "db_name" {
  description = "Nome do banco criado na instância."
  value       = var.db_name
}

output "db_security_group_id" {
  description = "SG do RDS. Só libera 5432 para os pods do EKS e para a Lambda."
  value       = aws_security_group.rds.id
}

output "lambda_security_group_id" {
  description = <<-EOT
    SG que a Lambda de autenticação deve usar. Criado aqui porque o ingress do
    RDS precisa referenciá-lo — ver o comentário em `rds.tf`.
  EOT
  value       = aws_security_group.lambda_auth.id
}

output "api_secret_name" {
  description = "Nome do segredo no Secrets Manager com DATABASE_URL e chaves JWT."
  value       = aws_secretsmanager_secret.api.name
}

output "api_secret_arn" {
  description = <<-EOT
    ARN do segredo. Vai na policy de leitura da Lambda e é usado pelo
    External Secrets / Secrets Store CSI driver no cluster.
  EOT
  value       = aws_secretsmanager_secret.api.arn
}

output "create_k8s_secret_command" {
  description = <<-EOT
    Atalho para materializar o Secret do Kubernetes a partir do Secrets
    Manager, enquanto o External Secrets Operator não estiver no ar.
  EOT
  value       = <<-EOT
    aws secretsmanager get-secret-value \
      --secret-id ${aws_secretsmanager_secret.api.name} \
      --query SecretString --output text \
    | jq -r 'to_entries | map("--from-literal=\(.key)=\(.value)") | join(" ")' \
    | xargs kubectl -n tech-challenge create secret generic api-secrets
  EOT
}
