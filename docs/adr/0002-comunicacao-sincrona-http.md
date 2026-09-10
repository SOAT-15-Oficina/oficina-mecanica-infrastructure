# ADR-0002 — Comunicação síncrona HTTP, sem broker de mensagens

- **Estado:** Aceita
- **Data:** 2026-09-02
- **Relacionada:** [RFC-0005](../rfc/0005-segregacao-em-repositorios.md), [ADR-0003](0003-api-gateway-como-unica-porta-publica.md)

## Contexto

O sistema tem duas unidades de execução: o monolito modular em Kubernetes e a
Lambda de autenticação. A fase exige segregação em repositórios, e segregar
repositórios convida a segregar também o *runtime* — filas, eventos, um serviço
por bounded context.

O domínio, porém, é um agregado só. Abrir uma OS, adicionar serviços, aprovar
itens e recalcular o total são operações que tocam as mesmas tabelas e precisam
de consistência imediata: o cliente clica em "aprovar" e espera ver o novo
status na mesma resposta.

## Decisão

**Toda comunicação entre componentes é HTTP síncrono, roteado pelo API Gateway.
Nenhum broker, nenhuma fila, nenhum evento assíncrono entre serviços.**

Concretamente:

- O painel web chama o API Gateway. Nada mais.
- A Lambda e o monolito **não se chamam**. O acoplamento entre eles é o segredo
  do JWT e o schema do banco — ver [ADR-0009](0009-jwt-hs256-com-segredo-compartilhado.md).
- O único trabalho fora da requisição é o envio de e-mail via SES, e mesmo ele
  é disparado dentro do handler: falha de envio é registrada em log e **não**
  derruba a operação de negócio.
- Repositórios se coordenam por dado, não por chamada: identificadores no SSM
  Parameter Store ([ADR-0007](0007-contrato-entre-repositorios-via-ssm.md)).

## Alternativas consideradas

**SQS + workers para notificação.** Tornaria o envio de e-mail resiliente a
falha do SES e daria retry automático. Custo: mais um recurso no Terraform, mais
um consumidor a operar, e a necessidade de idempotência no envio. O ganho real —
não perder um e-mail de orçamento — é hoje coberto pelo fato de que o orçamento
é reenviado a cada alteração de item enquanto a OS está em
`AGUARDANDO_APROVACAO`.

**EventBridge entre monolito e Lambda.** Não há evento a trocar. A Lambda emite
token e vai embora; o monolito valida offline.

**Serviços separados por bounded context (clientes, OS, catálogo).** Multiplicaria
transações distribuídas por um domínio que cabe numa transação de banco. Seria
sofisticação sem problema correspondente.

## Consequências

**Positivas**
- Consistência forte sem saga, sem compensação, sem outbox.
- Um caminho de requisição para depurar, e ele aparece inteiro no access log do
  API Gateway.
- Latência previsível: sem fila, sem *lag* de consumidor.

**Negativas**
- **Falha do SES é falha silenciosa.** O e-mail some, e só o log registra. É o
  preço aceito conscientemente; a mitigação é alerta sobre a taxa de erro de
  envio ([RFC-0004](../rfc/0004-estrategia-de-observabilidade.md)).
- **Acoplamento temporal.** Se o RDS estiver lento, tudo fica lento — não há
  buffer.
- Picos de escrita são absorvidos por escala horizontal (HPA), não por fila. O
  teto passa a ser o `max_connections` do RDS.
