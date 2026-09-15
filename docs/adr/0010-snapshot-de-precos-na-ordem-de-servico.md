# ADR-0010. Snapshot de preços na ordem de serviço

**Aceita** · 2026-09-02 · Relacionada: [modelo de dados](../banco-de-dados.md)

**Contexto.** Um item de OS referencia um serviço do catálogo (`services`) e
insumos (`supplies`). O caminho normalizado seria guardar só a FK e ler preço e
tempo do catálogo sempre que preciso. O problema aparece na linha do tempo do
negócio: na segunda-feira a oficina envia um orçamento de R$ 450 e o cliente
aprova por e-mail; na terça o catálogo é reajustado e o mesmo serviço passa a
R$ 520; na quarta o cliente abre a consulta pública e vê R$ 520 em uma OS que
aprovou por R$ 450. O efeito não é apenas técnico: o valor aprovado por e-mail
é um compromisso contratual com o cliente.

**Decisão.** No momento em que um item entra na OS, copiar do catálogo título,
descrição, preço e tempo estimado para colunas `*_snapshot` da própria linha. O
valor cobrado sai do snapshot; a FK permanece apenas para rastreabilidade e
relatórios.

```
work_order_services
  service_id                                FK, de onde veio
  service_title_snapshot                    o que foi vendido
  service_description_snapshot
  service_price_cents_snapshot              por quanto
  service_estimated_time_minutes_snapshot   prometido em quanto tempo

work_order_service_supplies
  supply_id
  supply_title_snapshot
  supply_price_cents_snapshot
  supply_quantity
```

`total_estimated_price_cents` da OS é a soma dos snapshots e, após a decisão do
cliente, apenas dos itens com `approval_status = APROVADO`. Itens só podem ser
adicionados ou removidos em `RECEBIDA`, `EM_DIAGNOSTICO` ou
`AGUARDANDO_APROVACAO`: depois de aprovada, a composição está congelada, e o
snapshot garante que os valores também.

## Alternativas descartadas

| Opção | Motivo do descarte |
|---|---|
| Ler sempre do catálogo | normalizado e mais enxuto, mas produz o cenário do contexto |
| Versionar o catálogo (`services_versions` e FK para a versão) | preserva histórico e evita duplicação, ao custo de uma tabela a mais, uma junção a mais em toda leitura de OS e a necessidade de decidir o que conta como nova versão. Para um catálogo de dezenas de linhas que muda raramente, o snapshot entrega o mesmo resultado sem a junção |
| Soft delete com imutabilidade no catálogo | empurra a complexidade para a tela de cadastro e confunde o operador, que espera poder corrigir um erro de digitação no título |

## Consequências

| Ganhos | Custos |
|---|---|
| Orçamento aprovado é imutável por construção, sem trigger e sem coluna de versão | **desnormalização assumida**: o título aparece em duas tabelas, e corrigir um erro de digitação no catálogo não corrige OSs antigas. É o desejado, mas surpreende quem espera propagação |
| O catálogo pode ser reajustado ou ter itens desativados sem risco para OSs abertas | mais colunas e mais escrita por item |
| Leitura de OS não faz junção com o catálogo: uma consulta a menos no caminho mais frequente | a FK `service_id` pode apontar para um registro que não descreve mais o que foi vendido, e relatórios que juntem com `services` precisam saber disso |
| O histórico registra o que foi **vendido**, informação correta para relatório financeiro | |
