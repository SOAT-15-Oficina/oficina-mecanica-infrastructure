# ADR-0011 — Logs estruturados com correlação de requisições

- **Estado:** Proposta
- **Data:** 2026-09-02
- **Relacionada:** [RFC-0004](../rfc/0004-estrategia-de-observabilidade.md)

## Contexto

Hoje o monolito e a Lambda registram com a biblioteca padrão `log`, em texto
livre:

```
budget: send email for work order 3f2a...: dial tcp: i/o timeout
work order status notification: find customer for work order 3f2a...: no rows
```

Três limitações concretas:

1. **Não é consultável.** Achar "todos os erros de envio de e-mail da última
   hora" exige `grep` sobre texto, e o formato muda de mensagem para mensagem.
2. **Não correlaciona.** Uma requisição que passa pelo CloudFront, pelo API
   Gateway, pelo ALB e por um dos até 10 pods deixa rastros em quatro lugares,
   sem identificador comum. Com o HPA ativo, as linhas de uma mesma operação
   podem estar em pods diferentes.
3. **Não tem nível nem contexto fixo.** Tudo é a mesma coisa: não dá para
   alertar sobre `ERROR` sem alertar sobre tudo.

O access log do API Gateway **já** é JSON e já carrega `$context.requestId` — o
elo existe na borda e se perde ao entrar na aplicação.

## Decisão proposta

**Adotar `log/slog` com handler JSON em todos os componentes Go, e propagar um
identificador de correlação da borda até a última linha de log.**

### 1. Identificador de correlação

O API Gateway passa a injetar o próprio `requestId` como header na integração,
via *parameter mapping*:

```
append:header.x-request-id = $context.requestId
```

Assim o identificador que aparece no access log do gateway é o mesmo que a
aplicação recebe. Se o header vier ausente (chamada interna, teste local), a
aplicação gera um UUID.

### 2. Middleware no monolito

Primeiro middleware da cadeia, antes de `Auth`:

- lê `X-Request-Id` (ou gera);
- coloca um `*slog.Logger` já decorado no `context.Context` da requisição;
- devolve o mesmo id no header da resposta;
- ao final, emite uma linha de acesso com método, rota, status e duração.

Todo log dentro do handler sai do logger do contexto — nunca do global.

### 3. Taxonomia de campos

Campos fixos, iguais nos dois runtimes:

| Campo | Origem | Exemplo |
|---|---|---|
| `time`, `level`, `msg` | `slog` | — |
| `service` | build | `monolith`, `auth-lambda` |
| `env` | variável de ambiente | `homolog`, `prod` |
| `version` | SHA do commit | `16c3616` |
| `request_id` | header ou gerado | `Kx9...` |
| `route`, `method`, `status`, `duration_ms` | linha de acesso | `/work-orders` |
| `user`, `role` | claims do JWT, quando houver | `admin` |
| `work_order_id`, `work_order_code` | quando a operação tiver uma OS | — |
| `error` | `err.Error()` em `level=ERROR` | — |

**Nunca** entram em log: `password`, `password_hash`, o token, o segredo JWT, e
o `document` do cliente (CPF/CNPJ é dado pessoal — usa-se `customer_id`).

### 4. Eventos de domínio explícitos

Além da linha de acesso, eventos nomeados para o que os dashboards e alertas
precisam contar:

| Evento | Nível | Quando |
|---|---|---|
| `work_order.created` | INFO | OS aberta |
| `work_order.status_changed` | INFO | transição aceita, com `from` e `to` |
| `work_order.transition_rejected` | WARN | transição inválida |
| `budget.sent` / `budget.send_failed` | INFO / ERROR | envio do orçamento |
| `approval.decided` | INFO | cliente aprovou ou reprovou |
| `purchase_alert.sent` | INFO | falta de insumo detectada |
| `auth.login_failed` | WARN | credencial inválida |

São esses eventos, e não `grep` em texto, que alimentam o **alerta de falha no
processamento de ordens de serviço** exigido na fase.

### 5. Lambda

Mesmo handler JSON e mesma taxonomia. `request_id` vem do
`events.APIGatewayV2HTTPRequest.RequestContext.RequestID`, que é exatamente o
`$context.requestId` do access log.

## Alternativas consideradas

**`zerolog` ou `zap`.** Mais rápidos e com API mais rica. `slog` é biblioteca
padrão desde o Go 1.21, não adiciona dependência, e a diferença de desempenho é
irrelevante para o volume aqui.

**Só o access log do API Gateway.** Já existe e é JSON, mas para no gateway: não
enxerga nada de dentro da aplicação, e não sabe *por que* um 500 aconteceu.

**Tracing distribuído (OpenTelemetry) em vez de correlação por id.** É o passo
seguinte, e o `request_id` é pré-requisito dele, não substituto. Registrado na
[RFC-0004](../rfc/0004-estrategia-de-observabilidade.md).

## Consequências

**Positivas**
- Uma requisição vira uma consulta: `request_id = "..."` devolve o rastro
  inteiro, incluindo o access log da borda.
- Alerta por `level` e por evento nomeado, sem depender de texto de mensagem.
- Campos `env` e `version` permitem separar homologação de produção e atribuir
  uma regressão a um deploy.

**Negativas**
- Toque em todos os pontos que hoje chamam `log.Printf` — mecânico, mas amplo.
- Log JSON é ilegível no terminal sem `jq`. Mitigação: handler de texto quando
  `ENV=local`.
- Volume maior de bytes por linha, com efeito em custo de ingestão.
- Disciplina permanente: campo novo precisa entrar na taxonomia, e é fácil
  vazar dado pessoal em `slog.Any` de uma struct inteira. Mitigação: registrar
  os tipos de domínio com `LogValue()` que omite campos sensíveis.
