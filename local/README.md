# Ambiente local completo

Sobe a Fase 4 inteira numa máquina: painel, Lambda de autenticação, OS Service,
Billing, Execution, dois PostgreSQL, LocalStack (SQS/SNS FIFO e DynamoDB),
MailHog e o Mercado Pago falso, atrás de um nginx que faz o papel do
CloudFront e do API Gateway.

## Pré-requisitos

Os repositórios clonados lado a lado:

```text
study/
  oficina-mecanica-infrastructure/   <- este repositório
  oficina-mecanica-monolith/         <- OS Service (renomeado para -os-service no GitHub)
  oficina-mecanica-billing-service/
  oficina-mecanica-execution-service/
  oficina-mecanica-serverless/
  oficina-mecanica-frontend/
```

O contexto de build do OS Service é `../../oficina-mecanica-monolith` por
padrão. Se o clone local já tiver o nome novo, aponte a variável:

```bash
export OS_SERVICE_CONTEXT=../../oficina-mecanica-os-service
```

## Subir

```bash
docker compose -f local/docker-compose.local.yml up --build
```

A ordem é resolvida pelo compose: LocalStack fica saudável, o
`localstack-init` cria filas, tópicos, assinaturas e a tabela e termina; os
bancos ficam prontos e as migrations do OS e do Billing rodam (`migrate`) e
terminam; só então os três serviços sobem. Derrubar e limpar:

```bash
docker compose -f local/docker-compose.local.yml down -v
```

## URLs

| O quê | URL |
|---|---|
| Painel | http://localhost:8080 |
| API (OS Service) | http://localhost:8080/api/ |
| Swagger do OS Service | http://localhost:8080/api/swagger |
| Swagger do Billing | http://localhost:8080/api/billing/swagger |
| Swagger do Execution | http://localhost:8080/api/execution/swagger |
| Login e cadastro (Lambda) | `POST http://localhost:8080/api/auth/login`, `POST .../api/auth/register` |
| MailHog (e-mails de orçamento, pagamento e status) | http://localhost:8025 |
| Mercado Pago falso | http://localhost:8095 (`/__health`, `/__orders/{id}`) |
| LocalStack | http://localhost:4580 |

Só essas quatro portas são publicadas (8080, 8025, 8095 e 4580). Os bancos e
os serviços ficam apenas na rede do compose.

## Roteamento

O `nginx.conf` replica o CloudFront (tira o prefixo `/api`) e o API Gateway
(escolhe o destino pelo prefixo), na mesma ordem de precedência da AWS:

| Prefixo no navegador | Destino | Caminho que o serviço recebe |
|---|---|---|
| `/api/auth/` | `lambda-shim` → Lambda no RIE | `/auth/...` |
| `/api/billing/` | `billing:8080` | `/billing/...` |
| `/api/execution/` | `execution:8080` | `/execution/...` |
| `/api/` | `os-service:8080` | `/...` |
| `/` | arquivos do `oficina-mecanica-frontend` | — |

O nginx resolve os nomes no DNS do Docker a cada requisição, então ele sobe
mesmo que um serviço ainda esteja reiniciando.

## Mensageria no LocalStack

Criado por `localstack/init.sh` (conta `000000000000`, região `sa-east-1`). O
script é idempotente: rodar de novo não duplica nada.

| Recurso | Detalhe |
|---|---|
| `os-inbox.fifo`, `billing-inbox.fifo`, `execution-inbox.fifo` | FIFO, sem deduplicação por conteúdo, visibilidade de 60s, DLQ com `maxReceiveCount = 5` |
| `os-inbox-dlq.fifo`, `billing-inbox-dlq.fifo`, `execution-inbox-dlq.fifo` | FIFO |
| `billing-events.fifo`, `execution-events.fifo` | tópicos SNS FIFO |
| assinaturas | `os-inbox.fifo` assina os dois tópicos com `RawMessageDelivery=true`: o corpo na fila é o envelope JSON |
| `execution-tickets` | DynamoDB `PK`/`SK`, GSI `queue` (`GSI1PK`/`GSI1SK`), TTL em `expires_at` |

Inspecionar de fora:

```bash
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=sa-east-1
aws --endpoint-url http://localhost:4580 sqs get-queue-attributes \
  --queue-url http://localhost:4580/000000000000/os-inbox-dlq.fifo \
  --attribute-names ApproximateNumberOfMessages
aws --endpoint-url http://localhost:4580 sqs receive-message \
  --queue-url http://localhost:4580/000000000000/os-inbox.fifo --visibility-timeout 0
```

## Valores fixos

| Variável | Valor | Quem usa |
|---|---|---|
| `JWT_SECRET_KEY` | `local-dev-secret` | Lambda assina; os três serviços validam |
| `INTERNAL_SERVICE_TOKEN` | `local-internal-token` | Lambda envia em `X-Service-Token`; OS Service confere |
| `MERCADOPAGO_WEBHOOK_SECRET` | `local-webhook-secret` | mpfake assina o webhook; Billing valida |
| `MERCADOPAGO_BASE_URL` | `http://mpfake:8095` | Billing |
| `MPFAKE_WEBHOOK_URL` | `http://billing:8080/billing/webhooks/mercadopago` | para onde o fake envia o webhook da order (no Mercado Pago real, a URL fica no painel) |
| `MERCADOPAGO_POS_EXTERNAL_ID` | `OFICINAMATRIZPOS01` | caixa onde as orders QR sao criadas (Billing e fake) |
| `APP_BASE_URL` | `http://localhost:8080/api` | links enviados por e-mail |

Os prazos da Saga aceitam sobrescrita pelo ambiente, para demonstrar
expiração sem esperar dias:

```bash
SAGA_APPROVAL_TIMEOUT=2m SAGA_PAYMENT_TIMEOUT=2m PAYMENT_EXPIRATION=2m \
  docker compose -f local/docker-compose.local.yml up
```

`SAGA_TICK`, `SAGA_COMMAND_TIMEOUT` e `SAGA_MAX_ATTEMPTS` também.

## Percorrer uma OS e simular o pagamento

1. Crie um usuário e faça login pelo painel (ou por `POST /api/auth/register`
   e `POST /api/auth/login`).
2. Cadastre cliente e veículo e abra a OS (`POST /api/work-orders`). A Saga
   começa e o Execution põe a OS na fila de diagnóstico
   (`GET /api/execution/queue?branch=MATRIZ&phase=DIAGNOSTICO`).
3. Inicie o diagnóstico, inclua os itens na OS e conclua o diagnóstico
   (`POST /api/execution/tickets/{id}/diagnosis/start` e `.../complete`). O
   Billing gera o orçamento e manda o e-mail.
4. No MailHog, abra o e-mail do orçamento e clique em aprovar (os links vão para
   `http://localhost:8080/api/billing/public/quotes/...`).
5. O Billing cria uma order de QR Code dinâmico no mpfake e manda o e-mail com
   o link da página do QR (`/api/billing/public/payments/{id}/qr`). A mesma
   página aparece como `payment_url` na consulta pública da OS e no detalhe da
   OS do painel, com a imagem e o "copia e cola". O id da order (`ORDTST...`)
   está em `payments[].provider_order_id` de
   `GET /api/billing/quotes/by-work-order/{id}`.
6. Pague: abra `http://localhost:8095/__orders/{orderId}` e clique em
   **Pagar** ou **Expirar**. Sem navegador:

   ```bash
   curl -X POST "http://localhost:8095/__orders/<orderId>/pay"
   curl -X POST "http://localhost:8095/__orders/<orderId>/expire"
   ```

   O fake muda o status da order e chama o webhook do Billing (`type=order`)
   com `x-signature` assinado; o Billing consulta `GET /v1/orders/{id}` no fake
   e publica `billing.payment-confirmed` (ou `payment-failed` com `EXPIRADO`).
7. Com o pagamento confirmado o reparo entra na fila. Inicie e finalize cada
   item pelo Execution; ao finalizar o último, a OS fica `FINALIZADA`.
   Acompanhe por `GET /api/work-orders/{id}/history` e
   `GET /api/work-orders/{id}/saga`.

**Compensação completa (caso C da RFC-0006):** antes de pagar, marque a bancada
como indisponível. O Execution recusa o reparo, o Billing estorna no mpfake e a
OS termina `CANCELADA`.

```bash
curl -X PUT http://localhost:8080/api/execution/bays/MATRIZ/availability \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"available":false}'
```
