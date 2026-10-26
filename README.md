# tech-challenge-fiap-infra-db

Infraestrutura do banco de dados gerenciado do Tech Challenge, em Terraform.

É o **segundo** repositório da cadeia de deploy. Depende do `infra-k8s` e é
consumido pelo `lambda-auth` e pelo `app-oficina`.

## Propósito

- **RDS PostgreSQL 16** em subnets privadas, sem acesso público, com storage
  criptografado.
- **Security groups**: o do RDS, que libera 5432 apenas para os pods do EKS e
  para a Lambda; e o da própria Lambda, criado aqui para evitar dependência
  circular (ver abaixo).
- **Segredo no Secrets Manager** com a `DATABASE_URL` montada e as chaves JWT
  compartilhadas entre quem assina e quem valida o token.

## Tecnologias

Terraform ~> 1.13 · AWS Provider ~> 6.0 · módulo `terraform-aws-modules/rds`
· AWS Secrets Manager · GitHub Actions com OIDC.

## Arquitetura deste repositório

```
   infra-k8s (remote state)
   vpc_id · private_subnet_ids · cluster_primary_security_group_id
            │
            ▼
   ┌─────────────────────────────────────────────────┐
   │ VPC — subnets privadas                          │
   │                                                 │
   │   SG lambda-auth ──┐                            │
   │   (criado aqui)    │ 5432                       │
   │                    ▼                            │
   │   SG eks ────────► SG rds ──► RDS PostgreSQL 16 │
   │            5432               nao publico       │
   └─────────────────────────────────────────────────┘
            │
            ▼
   Secrets Manager  tech-challenge-fiap/api
   DATABASE_URL · JWT_ACCESS_SECRET · JWT_REFRESH_SECRET
            │
            ├──► lambda-auth  (assina o JWT)
            └──► app-oficina  (valida o JWT, conecta no banco)
```

### Outputs que as outras stacks consomem

| Output | Quem lê | Para quê |
|---|---|---|
| `api_secret_arn` | lambda-auth, app-oficina | policy de leitura do segredo |
| `api_secret_name` | lambda-auth, app-oficina | `GetSecretValue` em runtime |
| `lambda_security_group_id` | lambda-auth | VPC config da função |
| `db_endpoint` | diagnóstico | marcado `sensitive` |

## Execução

Pré-requisito: o pipeline do `infra-k8s` já aplicado (a VPC e o cluster
precisam existir).

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply          # ~10 min para o RDS ficar disponível
```

Para conferir o segredo gerado:

```bash
aws secretsmanager get-secret-value \
  --secret-id "$(terraform output -raw api_secret_name)" \
  --query SecretString --output text | jq 'keys'
```

### Destruir

Antes de destruir o `infra-k8s` — o RDS vive nas subnets daquela VPC e
segura o `destroy` dela:

```bash
terraform destroy
```

## CI/CD

| Gatilho | O que roda |
|---|---|
| Pull request para `main`/`dev` | `fmt`, `validate` e `plan`; o plan vira comentário no PR |
| Push em `main` | `apply` |

Configure antes do primeiro push:

- Secret `AWS_TERRAFORM_ROLE_ARN` — output `github_terraform_role_arn` do
  `infra-k8s`.
- Variable `AWS_REGION`.
- Secret `NEWRELIC_LICENSE_KEY` (opcional) — License Key INGEST do New Relic. O
  workflow a passa como `TF_VAR_newrelic_license_key`, e ela entra no JSON do
  segredo da API como `NR_LICENSE_KEY`. Sem o secret, o pipeline roda igual e a
  chave fica fora do JSON — o `app-oficina` sobe sem telemetria.

A branch `main` é protegida: merge só via Pull Request.

## Decisões que vale conhecer

### O SG da Lambda nasce aqui, não no repositório da Lambda

O ingress do RDS precisa referenciar o security group da Lambda, e um SG não
pode ser referenciado antes de existir. Se ele nascesse no `lambda-auth`,
haveria dependência circular: a Lambda esperando o RDS e o RDS esperando o SG
da Lambda. Criando-o aqui, o grafo fica numa direção só — esta stack cria e
exporta, a outra apenas consome.

### A chave do JWT mora junto do banco

A Lambda **assina** o token e o authorizer do API Gateway o **valida**. Se
cada um gerasse a própria chave, todo token emitido seria recusado na porta de
entrada. Uma chave só, no Secrets Manager, lida pelos dois. Ela fica neste
repositório porque é aqui que o segredo compartilhado é composto, junto com a
`DATABASE_URL`.

### `sslmode=require&uselibpqcompat=true` na connection string

O RDS Postgres ≥ 15 vem com `rds.force_ssl=1`: sem TLS a conexão é recusada.
Só que no driver `pg` do Node, `require` sozinho se comporta como
`verify-full` e derruba a conexão com *self-signed certificate in chain* (a CA
do RDS não está no trust store). Com `uselibpqcompat=true`, `require`
criptografa sem exigir a CA — mesmo comportamento do `psql`. O engine do
Prisma aceita e ignora o parâmetro extra.

### `recovery_window_in_days = 0`

Sem isso, destruir a stack agenda o segredo para exclusão com janela de 7 a 30
dias e o próximo `apply` falha com *already scheduled for deletion*, porque o
nome continua ocupado. Numa stack que sobe e desce todo dia, isso trava tudo.

### Sem Multi-AZ, sem backup, sem deletion protection

A stack é feita para subir e descer e o custo é o critério. Com deletion
protection ligada ou snapshot final obrigatório, o `terraform destroy` falha e
sobra instância rodando — exatamente o que se quer evitar. **Não é
configuração de produção**; a justificativa formal e o que mudaria num
ambiente real estão no ADR de banco de dados, no repositório de documentação.

## Repositórios da entrega

| Repositório | Papel |
|---|---|
| [infra-k8s](https://github.com/pedruvaz/tech-challenge-fiap-infra-k8s) | VPC, EKS, ECR, OIDC |
| [infra-db](https://github.com/pedruvaz/tech-challenge-fiap-infra-db) | **este** — RDS e Secrets Manager |
| [lambda-auth](https://github.com/pedruvaz/tech-challenge-fiap-lambda-auth) | autenticação por CPF, emissão do JWT |
| [app-oficina](https://github.com/pedruvaz/tech-challenge-fiap-app-oficina) | API da oficina no EKS |
