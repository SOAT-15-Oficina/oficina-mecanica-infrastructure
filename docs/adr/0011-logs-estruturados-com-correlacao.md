# ADR-0011. Logs estruturados com correlação de requisições

**Proposta** · 2026-09-02 · Relacionada [RFC-0004](../rfc/0004-estrategia-de-observabilidade.md)

**Contexto.** O monolito e a Lambda registram com a biblioteca padrão `log`, em
texto livre. Três limitações concretas: não é consultável, porque achar todos
os erros de envio de e-mail da última hora exige `grep` sobre texto cujo
formato muda de mensagem para mensagem; não correlaciona, porque uma requisição
que passa pelo CloudFront, pelo API Gateway, pelo ALB e por um dos até 10 pods
deixa rastros em quatro lugares sem identificador comum; e não tem nível, o que
impede alertar sobre `ERROR` sem alertar sobre todo o resto.

O access log do API Gateway **já** é JSON e já carrega `$context.requestId`: o
elo existe na borda e se perde ao entrar na aplicação.

**Decisão.** Adotar `log/slog` com handler JSON em todos os componentes Go, e
propagar um identificador de correlação da borda até a última linha de log.

**1. Identificador de correlação.** O API Gateway injeta o próprio `requestId`
como header na integração, via *parameter mapping*:

```
append:header.x-request-id = $context.requestId
```

O uso de `append:` em vez de `overwrite:` tem consequência: se o cliente mandou
um `X-Request-Id`, ele continua na requisição, **antes** do valor do gateway.
**A aplicação usa o último valor**, que é o único que ela sabe ter nascido na
borda. Header de cliente é entrada não confiável, não pode virar chave de
correlação e não deve chegar a um campo de log sem filtro. Se o header vier
ausente, em chamada interna ou teste local, a aplicação gera um UUID.

**2. Middleware no monolito.** Primeiro da cadeia, antes de `Auth`: lê o último
`X-Request-Id`, ou gera um, e o descarta se não passar por um filtro de
caracteres; coloca um `*slog.Logger` decorado no `context.Context`; devolve o
mesmo id no header da resposta; e ao final emite uma linha de acesso com
método, rota, status e duração. Todo log dentro do handler sai do logger do
contexto, e nunca do global.

**3. Taxonomia de campos**, igual nos dois runtimes:

| Campo | Origem |
|---|---|
| `time`, `level`, `msg` | `slog` |
| `service` | build: `monolith`, `auth-lambda` |
| `env` | variável de ambiente: `homolog`, `prod` |
| `version` | SHA do commit |
| `request_id` | header ou gerado |
| `route`, `method`, `status`, `duration_ms` | linha de acesso |
| `http.status_code` | linha de acesso, ao lado de `status` |
| `user`, `role` | claims do JWT, quando houver |
| `work_order_id`, `work_order_code` | quando a operação tiver uma OS |
| `event` | nome do evento de domínio |
| `decision` | resultado de `approval.decided` |
| `integration` | dependência externa, em `level=ERROR`: `ses`, `rds`, `apigateway` |
| `error` | `err.Error()` em `level=ERROR` |

**Nunca** entram em log: `password`, `password_hash`, o token, o segredo JWT e
o `document` do cliente, porque CPF e CNPJ são dado pessoal. No lugar,
`customer_id`.

`http.status_code` existe além de `status` porque, no pré-processamento de log
JSON, o Datadog procura o *nível* do log em uma lista de atributos que começa
por `status`, o mesmo nome que a linha de acesso usa para o status HTTP. Se ele
o consumir, `@status` desaparece e o `group_by` de
`oficina.http_request_duration` fica sem a dimensão, sem nada quebrar
visivelmente. Emitir os dois faz a correção ser uma linha de Terraform em vez
de um novo deploy das duas aplicações.

**4. Eventos de domínio explícitos.** O nome vai em um campo próprio, `event`,
e não no `msg`: `msg` é texto para humano e muda na primeira refatoração;
`event` é identificador e não muda. É `@event` que as métricas de log e os
alertas consultam (`persistent/datadog_metrics.tf` e
`persistent/datadog_monitors.tf`).

| Evento | Nível | Quando |
|---|---|---|
| `work_order.created` | INFO | OS aberta |
| `work_order.status_changed` | INFO | transição aceita, com `from`, `to` e `duration_ms` no status anterior |
| `work_order.transition_rejected` | WARN | transição inválida |
| `budget.sent` e `budget.send_failed` | INFO e ERROR | envio do orçamento |
| `approval.decided` | INFO | cliente aprovou ou reprovou |
| `purchase_alert.sent` | INFO | falta de insumo detectada |
| `auth.login_failed` | WARN | credencial inválida |

São esses eventos que alimentam o alerta de falha no processamento de ordens de
serviço exigido no desafio.

**5. Lambda.** Mesmo handler JSON e mesma taxonomia. O `request_id` vem de
`events.APIGatewayV2HTTPRequest.RequestContext.RequestID`, que é exatamente o
`$context.requestId` do access log.

## Alternativas descartadas

| Opção | Motivo do descarte |
|---|---|
| `zerolog` ou `zap` | mais rápidos e com API mais rica, mas `slog` é biblioteca padrão desde o Go 1.21, não adiciona dependência, e a diferença de desempenho é irrelevante para o volume aqui |
| Só o access log do API Gateway | já existe e é JSON, mas para no gateway: não enxerga nada de dentro da aplicação e não registra por que um 500 aconteceu |
| Tracing distribuído em vez de correlação por id | é o passo seguinte, e o `request_id` é pré-requisito dele, não substituto ([RFC-0004](../rfc/0004-estrategia-de-observabilidade.md)) |

## Consequências

| Ganhos | Custos |
|---|---|
| Uma requisição vira uma consulta: `request_id = "..."` devolve o rastro inteiro, incluindo o access log da borda | exige tocar em todos os pontos que chamam `log.Printf`: trabalho mecânico, mas amplo |
| Os três painéis de negócio saem daqui, sem consulta ao banco | log JSON é ilegível no terminal sem `jq`. Mitigação: handler de texto quando `ENV=local` |
| Alerta por `level` e por evento nomeado, sem depender de texto de mensagem | volume maior de bytes por linha, com efeito em custo de ingestão |
| `env` e `version` permitem separar ambientes e atribuir uma regressão a um deploy | disciplina permanente: campo novo precisa entrar na taxonomia, e é fácil vazar dado pessoal em `slog.Any` de uma struct inteira. Mitigação: `LogValue()` nos tipos de domínio |
