# Visão geral do sistema

## O que o sistema faz

Gerencia o ciclo de vida de uma **ordem de serviço** (OS) de oficina mecânica,
do momento em que o veículo entra até a entrega:

1. O atendente cadastra cliente e veículo, e abre uma OS.
2. O mecânico registra o diagnóstico e adiciona serviços e insumos, escolhidos
   de um catálogo.
3. O sistema soma os itens e envia o orçamento por e-mail ao cliente.
4. O cliente aprova ou reprova cada serviço por links do próprio e-mail, sem
   criar conta.
5. A oficina executa os serviços aprovados, item por item.
6. O sistema notifica o cliente em cada mudança de status até a entrega.

Duas regras de negócio moldam o desenho todo:

- **O orçamento aprovado é imutável.** Reajuste no catálogo depois da aprovação
  não muda o valor da OS. É o que motiva a cópia de preço e prazo para dentro
  do item ([ADR-0010](./adr/0010-snapshot-de-precos-na-ordem-de-servico.md)).
- **Insumo em falta atrasa o prazo e aciona compras.** Quando os itens
  aprovados exigem mais insumo que o estoque, o prazo estimado recebe 2 dias e
  um alerta de compra é enviado.

## Os dois tipos de usuário

A divisão explica por que existem dois mecanismos de acesso, e não um.

| | Operadores | Clientes da oficina |
|---|---|---|
| Quem são | atendente, mecânico, administrador | o dono do veículo |
| Quantos | dezenas, todos cadastrados | milhares, nenhum cadastrado |
| Uso | diário | uma ou duas vezes por ano |
| O que fazem | cadastros, catálogos, OS, execução | aprovam orçamento e consultam status |
| Como acessam | painel web, login, JWT no header | link recebido por e-mail, sem login |

## Os quatro repositórios

O critério que separa um repositório do outro não é assunto, é **artefato
publicado**: cada um produz um artefato, com pipeline e ciclo de release
próprios ([RFC-0005](./rfc/0005-segregacao-em-repositorios.md)).

| Repositório | Responsabilidade | Artefato |
|---|---|---|
| `oficina-mecanica-infrastructure` | Terraform de AWS e Kubernetes, IAM e OIDC, rede, observabilidade. Dono desta documentação | recursos AWS e objetos Kubernetes |
| `oficina-mecanica-monolith` | API de negócio em Go no EKS. Dono do schema do banco | imagem de contêiner no ECR |
| `oficina-mecanica-serverless` | Lambda de autenticação: `POST /auth/login` e `POST /auth/register` | zip publicado na função |
| `oficina-mecanica-frontend` | painel web estático dos operadores | objetos no bucket S3 |

Antes de abrir um Pull Request, identifique qual artefato a mudança altera.
Corrigir um `.html` do painel não recompila Go nem toca no Terraform.

## Tecnologias em uso

| Camada | Tecnologia | Justificada em |
|---|---|---|
| Nuvem | AWS, região `sa-east-1` | [RFC-0001](./rfc/0001-escolha-da-nuvem.md) |
| Borda | CloudFront, 2 origens e uma CloudFront Function | [ADR-0003](./adr/0003-api-gateway-como-unica-porta-publica.md) |
| Porta de entrada | API Gateway HTTP API | [ADR-0003](./adr/0003-api-gateway-como-unica-porta-publica.md) |
| API de negócio | Go com Fiber v3, monolito modular | [ADR-0002](./adr/0002-comunicacao-sincrona-http.md) |
| Autenticação | AWS Lambda em Go, `provided.al2023` | [RFC-0003](./rfc/0003-estrategia-de-autenticacao.md) |
| Orquestração | Amazon EKS 1.31, com HPA | [ADR-0004](./adr/0004-hpa-no-deployment-da-api.md) |
| Banco de dados | Amazon RDS PostgreSQL 17 | [RFC-0002](./rfc/0002-escolha-do-banco-de-dados.md) |
| Migrations | `goose`, aplicadas por um `Job` | [ADR-0005](./adr/0005-migrations-como-job-do-pipeline.md) |
| E-mail | Amazon SES, acessado por IRSA | [ADR-0002](./adr/0002-comunicacao-sincrona-http.md) |
| Segredos | AWS Secrets Manager | [ADR-0009](./adr/0009-jwt-hs256-com-segredo-compartilhado.md) |
| Contrato entre repositórios | AWS SSM Parameter Store | [ADR-0007](./adr/0007-contrato-entre-repositorios-via-ssm.md) |
| Infraestrutura como código | Terraform, em duas camadas | [ADR-0006](./adr/0006-duas-camadas-de-terraform.md) |
| CI/CD | GitHub Actions, autenticação por OIDC | [ADR-0008](./adr/0008-oidc-para-os-pipelines.md) |
| Observabilidade | Datadog, New Relic como alternativa | [RFC-0004](./rfc/0004-estrategia-de-observabilidade.md) |
| Logs | `log/slog` JSON com `request_id` propagado | [ADR-0011](./adr/0011-logs-estruturados-com-correlacao.md) |

## O caminho de uma requisição

O painel vem de um bucket S3 privado, servido pelo CloudFront. A mesma
distribuição atende a API sob o prefixo `/api`, e uma CloudFront Function
remove esse prefixo antes de repassar à origem. Painel e API compartilham a
origem, logo não há CORS nem URL de API embutida no build do frontend.

A origem de `/api` é o API Gateway HTTP API, **única porta pública**. As rotas
de autenticação vão direto para a Lambda; todo o resto cai no `$default`, que
atravessa um VPC Link, chega a um ALB interno e termina em um pod da API.

A Lambda confere a senha contra `users` e devolve um JWT HS256. O pod valida
esse JWT localmente, sem chamar a Lambda: os dois compartilham apenas o
segredo, guardado no Secrets Manager ([ADR-0009](./adr/0009-jwt-hs256-com-segredo-compartilhado.md)). O pod executa a
regra de negócio contra o RDS, em subnet privada, e chama o SES dentro do
próprio handler quando precisa avisar alguém. Todo o percurso carrega o mesmo
`request_id` ([ADR-0011](./adr/0011-logs-estruturados-com-correlacao.md)).

## Três características que surpreendem quem chega

- **O ambiente sobe e desce.** Uma camada persistente custa cerca de US$ 1 por
  mês e vive sempre; uma camada efêmera custa cerca de US$ 0,30 por hora e
  existe só em uso. Desligado, o domínio público responde 404
  ([ADR-0006](./adr/0006-duas-camadas-de-terraform.md)).
- **Nada é alcançável da internet além do CloudFront.** ALB, EKS, RDS e Lambda
  estão em subnets privadas, sem IP público ([ADR-0003](./adr/0003-api-gateway-como-unica-porta-publica.md)).
- **A branch decide o ambiente.** Push em `hml` faz deploy em homologação;
  push em `main`, em produção. Nenhum workflow de aplicação aceita input de
  ambiente, e a regra é imposta também pela trust policy do IAM
  ([ADR-0008](./adr/0008-oidc-para-os-pipelines.md)).
