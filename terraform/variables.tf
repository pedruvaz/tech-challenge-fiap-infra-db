variable "aws_region" {
  description = "Região da AWS. Precisa bater com a do `infra-k8s`."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefixo e tag aplicados aos recursos."
  type        = string
  default     = "tech-challenge-fiap"
}

variable "db_instance_class" {
  description = "Classe da instância RDS. `db.t4g.micro` é elegível ao free tier nos 12 primeiros meses."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Armazenamento do RDS em GB. O mínimo do Postgres é 20."
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Nome do banco criado na instância."
  type        = string
  default     = "oficina"
}

variable "db_username" {
  description = "Usuário master do Postgres."
  type        = string
  default     = "oficina_admin"
}

variable "resend_api_key" {
  description = <<-EOT
    Chave da API da Resend (envio de e-mail de aprovação de orçamento).

    Opcional: com o default vazio a chave fica FORA do JSON do Secrets
    Manager, o deploy não a materializa no Secret k8s e o pod sobe normalmente
    (o secretKeyRef no Deployment é optional) — só o envio de e-mail fica
    inativo. Para ativar: TF_VAR_resend_api_key=<chave> terraform apply.
    É credencial de terceiro, então nasce fora do Terraform e entra por
    variável — nunca hardcoded nem gerada.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}
