resource "random_password" "db" {
  length = 32

  # O Postgres do RDS rejeita `/`, `@`, `"` e espaço na senha do master.
  # Além disso a senha entra numa connection string, onde `/` e `@` seriam
  # separadores — restringir aqui evita ter que fazer URL-encode depois.
  special          = true
  override_special = "!#%*-_=+"
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds"
  description = "Permite Postgres apenas a partir do cluster EKS e da Lambda de autenticacao."
  vpc_id      = local.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  security_group_id = aws_security_group.rds.id
  description       = "Postgres a partir dos pods do EKS"

  referenced_security_group_id = local.eks_security_group_id

  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"
}

# Security group da Lambda de autenticação.
#
# Ele nasce aqui, e não no repositório da Lambda, de propósito: o ingress do
# RDS precisa referenciá-lo, e um SG não pode ser referenciado antes de
# existir. Se ele nascesse lá, teríamos uma dependência circular entre as duas
# stacks — `lambda-auth` esperando o RDS e o RDS esperando o SG da Lambda.
# Aqui o grafo fica numa direção só: infra-db cria o SG e o exporta; a Lambda
# apenas o consome.
resource "aws_security_group" "lambda_auth" {
  name        = "${var.project_name}-lambda-auth"
  description = "SG da Lambda de autenticacao. Anexado pela stack lambda-auth."
  vpc_id      = local.vpc_id
}

# Egress liberado: a Lambda precisa alcançar o RDS e o Secrets Manager (este
# último via NAT ou VPC endpoint). Sem regra de saída, uma Lambda na VPC fica
# muda e a falha aparece como timeout, não como erro de permissão.
resource "aws_vpc_security_group_egress_rule" "lambda_auth_all" {
  security_group_id = aws_security_group.lambda_auth.id
  description       = "Saida liberada: RDS e Secrets Manager"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_lambda" {
  security_group_id = aws_security_group.rds.id
  description       = "Postgres a partir da Lambda de autenticacao"

  referenced_security_group_id = aws_security_group.lambda_auth.id

  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "${var.project_name}-db"

  engine               = "postgres"
  engine_version       = "16"
  family               = "postgres16"
  major_engine_version = "16"
  instance_class       = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result
  port     = 5432

  # Deixamos a senha no nosso próprio Secrets Manager (ver secrets.tf) para
  # poder montar a DATABASE_URL completa num único segredo. Com o
  # gerenciamento nativo da AWS, seria preciso ler o segredo dela e recompor.
  manage_master_user_password = false

  multi_az               = false
  publicly_accessible    = false
  create_db_subnet_group = true
  subnet_ids             = local.private_subnet_ids
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Esta stack é feita para subir e descer. Com deletion protection ligada ou
  # snapshot final obrigatório, o `terraform destroy` falha e sobra instância
  # rodando — que é exatamente o custo que queremos evitar.
  deletion_protection = false
  skip_final_snapshot = true

  backup_retention_period = 0
  create_monitoring_role  = false
}
# Demonstração do pipeline (PR do vídeo, não fazer merge)
