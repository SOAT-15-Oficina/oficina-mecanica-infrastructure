# ADR-0002. Comunicação síncrona HTTP, sem broker de mensagens

**Aceita** · 2026-09-02 · Relacionada [RFC-0005](../rfc/0005-segregacao-em-repositorios.md),
[ADR-0003](./0003-api-gateway-como-unica-porta-publica.md)

**Contexto.** O sistema tem duas unidades de execução: o monolito modular em
Kubernetes e a Lambda de autenticação. Segregar repositórios sugere segregar
também o *runtime*, com filas e um serviço por bounded context. O domínio,
porém, é um agregado só: abrir uma OS, adicionar serviços, aprovar itens e
recalcular o total tocam as mesmas tabelas e precisam de consistência
imediata, porque o cliente clica em "aprovar" e espera ver o novo status na
mesma resposta.

**Decisão.** Toda comunicação entre componentes é HTTP síncrono, roteado pelo
API Gateway. Nenhum broker, nenhuma fila, nenhum evento assíncrono entre
serviços.

- O painel web chama o API Gateway, e nada mais.
- A Lambda e o monolito **não se chamam**. O acoplamento entre eles é o segredo
  do JWT e o schema do banco ([ADR-0009](./0009-jwt-hs256-com-segredo-compartilhado.md)).
- O único trabalho fora da requisição é o envio de e-mail via SES, e ele é
  disparado dentro do handler. Falha de envio é registrada em log e **não**
  derruba a operação de negócio.
- Repositórios se coordenam por dado, não por chamada: identificadores no SSM
  ([ADR-0007](./0007-contrato-entre-repositorios-via-ssm.md)).

## Alternativas descartadas

| Opção | Motivo do descarte |
|---|---|
| SQS com workers para notificação | daria retry automático ao SES, ao custo de mais um recurso, mais um consumidor a operar e idempotência no envio. O ganho real, não perder um e-mail de orçamento, já é coberto pelo reenvio a cada alteração de item enquanto a OS está em `AGUARDANDO_APROVACAO` |
| EventBridge entre monolito e Lambda | não há evento a trocar: a Lambda emite o token e encerra, o monolito valida offline |
| Serviços por bounded context | multiplicaria transações distribuídas em um domínio que cabe em uma transação de banco |

## Consequências

| Ganhos | Custos |
|---|---|
| Consistência forte sem saga, compensação ou outbox | **falha do SES é silenciosa**: o e-mail não é enviado e só o log registra. Mitigação: alerta sobre a taxa de erro de envio ([RFC-0004](../rfc/0004-estrategia-de-observabilidade.md)) |
| Um caminho de requisição para depurar, inteiro no access log do gateway | **acoplamento temporal**: RDS lento deixa tudo lento, porque não há buffer |
| Latência previsível, sem fila e sem atraso de consumidor | picos de escrita são absorvidos por HPA, e o teto passa a ser o `max_connections` do RDS |
