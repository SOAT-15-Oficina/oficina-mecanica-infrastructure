# ADR-0010 — Snapshot de preços na ordem de serviço

- **Estado:** Aceita
- **Data:** 2026-09-02
- **Relacionada:** [modelo de dados](../banco-de-dados.md)

## Contexto

Um item de OS referencia um serviço do catálogo (`services`) e insumos
(`supplies`). O caminho normalizado seria guardar só a FK e ler preço e tempo do
catálogo sempre que preciso.

O problema aparece na linha do tempo do negócio:

1. Segunda: a oficina envia um orçamento de R$ 450 e o cliente aprova por e-mail.
2. Terça: o catálogo é reajustado — o mesmo serviço passa a R$ 520.
3. Quarta: o cliente abre a consulta pública e vê R$ 520 numa OS que aprovou por
   R$ 450.

Com leitura do catálogo, o valor de um documento já aprovado muda sozinho. Não é
um problema de consistência técnica: é um problema contratual.

## Decisão

**No momento em que um item entra na OS, copiar do catálogo título, descrição,
preço e tempo estimado para colunas `*_snapshot` da própria linha. O valor
cobrado sai do snapshot; a FK permanece apenas para rastreabilidade e
relatórios.**

```
work_order_services
  service_id                                FK — de onde veio
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

Consequências no cálculo: `total_estimated_price_cents` da OS é a soma dos
snapshots — e, após a decisão do cliente, apenas dos itens com
`approval_status = APROVADO`.

Itens só podem ser adicionados ou removidos enquanto a OS está em `RECEBIDA`,
`EM_DIAGNOSTICO` ou `AGUARDANDO_APROVACAO`. Depois de aprovada, a composição
está congelada — e o snapshot garante que os valores também.

## Alternativas consideradas

**Ler sempre do catálogo.** Normalizado e mais enxuto. Descartada pelo cenário
acima.

**Versionar o catálogo (`services_versions` + FK para a versão).** Solução
"correta" de livro: preserva o histórico e evita duplicação. Custo: uma tabela a
mais, uma junção a mais em toda leitura de OS, e a necessidade de decidir o que
conta como nova versão (mudar a descrição gera versão?). Para um catálogo de
dezenas de linhas que muda raramente, o snapshot entrega o mesmo resultado sem a
junção.

**Soft delete + imutabilidade no catálogo.** Serviço nunca alterado, só
substituído. Empurra a complexidade para a tela de cadastro e confunde o
operador, que espera poder corrigir um typo no título.

## Consequências

**Positivas**
- Orçamento aprovado é imutável por construção, sem trigger nem coluna de
  versão.
- O catálogo pode ser reajustado ou ter itens desativados sem risco para OSs
  abertas.
- Leitura de OS não faz junção com o catálogo: uma consulta a menos no caminho
  mais frequente do sistema.
- O histórico registra o que foi **vendido**, não o que o catálogo diz hoje —
  que é a informação certa para relatório financeiro.

**Negativas**
- **Desnormalização assumida.** Título de serviço aparece em duas tabelas;
  corrigir um typo no catálogo não corrige OSs antigas — e isso é exatamente o
  desejado, mas surpreende quem espera propagação.
- Mais colunas e mais escrita por item.
- A FK `service_id` pode apontar para um registro que não descreve mais o que
  foi vendido. Qualquer relatório que junte com `services` precisa saber disso;
  os que usam snapshot, não.
