# Segredos compartilhados entre a API, a Lambda de autenticação e o
# authorizer do API Gateway.
#
# Este segredo é o ponto de encontro das três peças, e é por isso que ele vive
# nesta stack e não na da Lambda: a Lambda **assina** o JWT e o authorizer o
# **valida** — se cada um gerasse a própria chave, todo token emitido seria
# recusado na porta de entrada. Uma chave só, num lugar só, lida por todos.

resource "random_password" "jwt_access" {
  length  = 64
  special = false
}

resource "random_password" "jwt_refresh" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "api" {
  name        = "${var.project_name}/api"
  description = "DATABASE_URL e segredos JWT consumidos pela API, pela Lambda e pelo authorizer."

  # Sem isto, destruir a stack agenda o segredo para exclusão com janela de
  # recuperação de 7 a 30 dias — e o próximo `apply` falha com "already
  # scheduled for deletion" porque o nome ainda está ocupado. Numa stack que
  # sobe e desce todo dia, isso trava tudo.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "api" {
  secret_id = aws_secretsmanager_secret.api.id

  # sslmode=require: o RDS Postgres >= 15 vem com rds.force_ssl=1 — sem TLS a
  # conexão é rejeitada ("no pg_hba.conf entry ... no encryption").
  # uselibpqcompat=true: no driver pg do Node, `require` sozinho vale como
  # verify-full e derruba a conexão com "self-signed certificate in chain"
  # (a CA do RDS não está no trust store); com o modo libpq, `require`
  # criptografa sem exigir a CA — mesmo comportamento do psql. O engine do
  # Prisma (migrate) aceita e ignora o parâmetro extra.
  # merge(): com resend_api_key ou newrelic_license_key vazias a chave nem
  # aparece no JSON — o deploy detecta a ausência e não a materializa no
  # Secret k8s correspondente.
  secret_string = jsonencode(merge(
    {
      DATABASE_URL = format(
        "postgresql://%s:%s@%s/%s?schema=public&sslmode=require&uselibpqcompat=true",
        var.db_username,
        urlencode(random_password.db.result),
        module.rds.db_instance_endpoint,
        var.db_name,
      )
      JWT_ACCESS_SECRET  = random_password.jwt_access.result
      JWT_REFRESH_SECRET = random_password.jwt_refresh.result
    },
    var.resend_api_key != "" ? { RESEND_API_KEY = var.resend_api_key } : {},
    var.newrelic_license_key != "" ? { NR_LICENSE_KEY = var.newrelic_license_key } : {},
  ))
}
