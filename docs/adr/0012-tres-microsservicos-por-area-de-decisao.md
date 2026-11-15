# ADR-0012. Três microsserviços por área de decisão

**Proposta** · 2026-11-11 · Origem [RFC-0006](../rfc/0006-microsservicos-e-saga.md) ·
Substitui [ADR-0002](./0002-comunicacao-sincrona-http.md)

**Contexto.** A oficina passou a operar em várias filiais, e o enunciado da
Fase 4 exige no mínimo três microsserviços com repositório, infraestrutura e
banco próprios, sem acesso de um serviço ao banco de outro. O monolito da
Fase 3 concentra atendimento, cobrança e bancada num único schema.

**Decisão.** O sistema é dividido pela área da oficina que **decide** sobre o
dado:

| Serviço | Decide sobre |
|---|---|
| OS Service | o que entra na OS, catálogos, estoque, usuários, ciclo de vida da OS |
| Billing Service | orçamento, decisão do cliente, cobrança e estorno |
| Execution Service | ordem da fila, diagnóstico e execução na bancada |

O que um serviço precisa do outro **viaja na mensagem** e é guardado como
cópia imutável: o comando de orçamento leva itens e preços congelados
([ADR-0010](./0010-snapshot-de-precos-na-ordem-de-servico.md)) e o e-mail do
cliente; o comando de reparo leva os itens aprovados. Nenhum serviço consulta
outro por HTTP para completar um dado que poderia ter recebido.

A Lambda de autenticação deixa de ler `users` no banco do OS Service e passa a
validar credenciais em `POST /internal/credentials/verify`, protegido por token
de serviço.

## Alternativas descartadas

| Opção | Motivo do descarte |
|---|---|
| Quarto serviço para catálogos | catálogo é lido na abertura da OS; extraí-lo põe uma chamada síncrona no caminho crítico sem requisito que a peça |
| Corte por entidade (cliente, veículo, OS) | gera serviços anêmicos que precisam uns dos outros em toda operação |
| Billing consultando a OS por HTTP | acoplamento temporal: orçamento não sairia com o OS Service fora do ar |
| Mover `users` para a Lambda | a OS referencia usuários (quem abriu, técnico); o painel de usuários teria de mudar de serviço junto |

## Consequências

| Ganhos | Custos |
|---|---|
| cada área evolui, escala e falha separada | consistência eventual entre os três |
| nenhum banco compartilhado | dados de cliente duplicados no Billing (nome e e-mail) |
| contratos explícitos em mensagem | três pipelines e três states para manter |
