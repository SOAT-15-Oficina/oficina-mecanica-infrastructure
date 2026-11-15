# ADR-0015. DynamoDB no Execution, PostgreSQL no OS e no Billing

**Proposta** · 2026-11-11 · Origem [RFC-0006](../rfc/0006-microsservicos-e-saga.md) ·
Relacionada [RFC-0002](../rfc/0002-escolha-do-banco-de-dados.md)

**Contexto.** O enunciado exige ao menos um banco SQL e um NoSQL, e banco
próprio por serviço.

**Decisão.**

| Serviço | Banco | Por quê |
|---|---|---|
| OS Service | PostgreSQL (RDS próprio) | mantém o schema relacional da Fase 3: OS, itens, catálogo e estoque com integridade referencial |
| Billing | PostgreSQL (RDS próprio) | dinheiro: unicidade de pagamento aprovado por orçamento, transação entre tabelas, auditoria em SQL |
| Execution | DynamoDB sob demanda | ficha por OS lida inteira pela chave, e fila consultada por filial e estado |

Modelo do Execution, tabela única:

| PK | SK | Conteúdo |
|---|---|---|
| `TICKET#<work_order_id>` | `META` | estado, filial, fase (diagnóstico ou reparo) |
| `TICKET#<work_order_id>` | `ITEM#<id>` | item aprovado e andamento |
| `TICKET#<work_order_id>` | `EVENT#<instante>` | linha do tempo da bancada |
| `MSG#<message_id>` | `MSG` | idempotência (escrita condicional, TTL) |
| `OUTBOX#<id>` | `OUTBOX` | mensagem a publicar |

GSI `queue`: `GSI1PK = QUEUE#<filial>#<estado>`, `GSI1SK = <enfileirado_em>`.

## Alternativas descartadas

| Opção | Motivo do descarte |
|---|---|
| MongoDB / DocumentDB | servidor ou cluster para operar; DocumentDB custa por instância parada |
| DynamoDB no Billing | sem transação relacional nem consulta ad hoc sobre pagamentos |
| Um RDS com três databases | atende "banco por serviço" só na credencial; o enunciado pede infraestrutura própria |

## Consequências

| Ganhos | Custos |
|---|---|
| custo zero com o Execution parado | dois RDS a mais no ambiente ligado |
| fila consultada por índice, sem varredura | padrões de acesso fixados no desenho; consulta nova pode exigir GSI novo |
| DynamoDB Local no compose e no CI | dois paradigmas de persistência no time |
