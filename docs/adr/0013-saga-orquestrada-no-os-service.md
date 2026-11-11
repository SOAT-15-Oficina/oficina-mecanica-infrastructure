# ADR-0013. Saga orquestrada no OS Service

**Proposta** · 2026-11-11 · Origem [RFC-0006](../rfc/0006-microsservicos-e-saga.md)

**Contexto.** Abrir a OS, diagnosticar, orçar, receber a decisão do cliente,
cobrar e enviar para a bancada atravessa os três serviços
([ADR-0012](./0012-tres-microsservicos-por-area-de-decisao.md)). Não existe mais
transação de banco que cubra o fluxo, e uma falha no meio precisa desfazer o
que já foi feito.

**Decisão.** Saga **orquestrada**, com o orquestrador dentro do OS Service, que
já é o dono do ciclo de vida da OS. O estado de cada saga é uma linha em
`saga_instances` (passo atual, passos concluídos, prazo, tentativas, motivo da
falha, versão para concorrência otimista).

- Participantes recebem **comandos** e respondem com **eventos**; não conhecem
  uns aos outros.
- Compensação na ordem inversa dos passos concluídos.
- **Pivô:** o aceite do reparo pela bancada. Depois dele a saga só anda para
  frente; cancelamento vira estorno manual.
- Cada passo de espera tem `deadline_at`. Comando sem resposta é reenviado com o
  mesmo `message_id` até 5 vezes e então compensado; orçamento não decidido e
  pagamento não feito no prazo são tratados como reprovação e recusa.
- Mensagem que não casa com o passo atual é descartada com log
  `saga.message_ignored`.

## Alternativas descartadas

| Opção | Motivo do descarte |
|---|---|
| Coreografia | fluxo sequencial com compensação em quase todo passo; espalhado em três consumidores, ninguém sabe dizer em que passo a OS está |
| Orquestrador em serviço próprio | um quarto deploy cujo único dado é o estado da OS, que já mora no OS Service |
| Motor de workflow (Temporal, Step Functions) | mais uma plataforma para operar e demonstrar; o fluxo cabe numa máquina de estados de nove passos |

## Consequências

| Ganhos | Custos |
|---|---|
| uma linha diz em que passo e por que uma OS parou | OS Service vira peça central; fora do ar, as sagas param (as mensagens esperam na fila) |
| compensação testável num só lugar | prazos e reenvio são código próprio, não da plataforma |
| participantes simples e substituíveis | o orquestrador precisa conhecer o contrato de todos |
