# RFC-0002 — Escolha do banco de dados

- **Estado:** Aceita
- **Data:** 2026-09-02
- **Detalhamento:** [modelo de dados](../banco-de-dados.md)
- **Decisões derivadas:** [ADR-0010](../adr/0010-snapshot-de-precos-na-ordem-de-servico.md), [ADR-0005](../adr/0005-migrations-como-job-do-pipeline.md)

## Problema

A fase exige **banco gerenciado** e uma **justificativa formal** da escolha,
somada a ajustes documentados no modelo relacional.

O domínio é uma ordem de serviço de oficina: cliente, veículo, catálogo de
serviços, catálogo de insumos, e a OS que amarra tudo com estado, aprovação do
cliente e dinheiro.

## O que o domínio exige

**Integridade referencial obrigatória.** Um `work_order_service` órfão é um
orçamento errado enviado a um cliente real. O schema tem onze `FOREIGN KEY`, e
nenhuma é decorativa.

**Transação multi-linha.** Aprovar um item recalcula o total da OS, pode
transicionar o status e pode disparar alerta de compra — escritas em três
tabelas que valem juntas ou não valem.

**Consulta analítica sem pipeline.** Volume diário de OS, tempo médio por status
e taxa de erro são `GROUP BY` sobre colunas de timestamp que já existem.

**Escrita modesta, leitura irregular.** Uma oficina abre dezenas de OS por dia,
não milhares por segundo. O pico é de leitura, quando um lote de orçamentos é
enviado e os clientes clicam nos links quase ao mesmo tempo.

**Dado pessoal.** Nome, CPF/CNPJ, e-mail e telefone de cliente — criptografia em
repouso e ausência de acesso público não são opcionais.

## Alternativas

### PostgreSQL no RDS — **recomendado**

**A favor.** Integridade e transação como padrão. Índice sobre expressão
(`CREATE UNIQUE INDEX ... ON services (LOWER(title))`) resolveu duplicidade de
título por diferença de caixa sem coluna extra nem trigger. `DEFERRABLE` nas FKs
deixa aberta a checagem adiada para carga em lote sem afetar o caminho normal.
Tipos ricos (`uuid` nativo, `jsonb` se necessário no futuro). Driver `pgx` maduro
em Go, com pool. Provider Terraform simples.

**Contra.** Instância dedicada custa por hora ligada. Escalar escrita é vertical.
Pool por processo multiplica conexões — a Lambda mantém pool por container quente
e o HPA sobe até 10 pods, então `max_connections` é um teto real.

### MySQL no RDS

**A favor.** Igualmente gerenciado, igualmente barato, também com FKs e
transações no InnoDB.

**Contra.** Sem índice sobre expressão até o 8.0.13 e, mesmo depois, com
comportamento menos direto; a solução usual para o caso de `LOWER(title)` seria
coluna gerada. Sem `uuid` nativo (`BINARY(16)` ou `CHAR(36)`). Menos confortável
em consulta analítica. Nenhuma vantagem que compensasse.

### Aurora Serverless v2

**A favor.** Escala automática de capacidade, compatível com PostgreSQL — a
resposta "certa" para carga irregular.

**Contra.** **O piso de 0,5 ACU cobra mesmo ocioso**, e ACU custa mais que a
instância `t` equivalente. Como o ambiente sobe e desce sob demanda, a
elasticidade não é aproveitada: paga-se pela capacidade de escalar sem que ela
seja exercida. Provisionamento mais lento no bring-up.

### DynamoDB

**A favor.** Cobrança por uso real, US$ 0 parado — perfeito para o ciclo
liga/desliga. Escala sem operação.

**Contra.** É o desalinhamento mais claro com o domínio. Sem junção, sem FK e sem
transação multi-item barata. O agregado OS→serviços→insumos até caberia num
documento, mas **catálogo de serviços e de insumos é compartilhado entre OSs** —
embuti-los duplicaria dado mutável, e mantê-los à parte exigiria junção na
aplicação. As consultas dos dashboards (`GROUP BY` por dia e por status) virariam
GSIs projetados ou um pipeline de agregação. Trocaria um problema que o SQL não
tem por dois que ele não tem.

### PostgreSQL em contêiner no próprio EKS

**A favor.** Custo marginal zero.

**Contra.** Viola o requisito de **banco gerenciado**, e estado em Kubernetes
exige `StatefulSet`, PVC, backup e plano de recuperação — trabalho de
infraestrutura sem relação com o domínio.

## Comparação

| | PostgreSQL RDS | MySQL RDS | Aurora Sv2 | DynamoDB |
|---|---|---|---|---|
| Integridade referencial | ✅ | ✅ | ✅ | ❌ |
| Transação multi-tabela | ✅ | ✅ | ✅ | limitada e cara |
| Analítica sem pipeline | ✅ | parcial | ✅ | ❌ |
| Índice sobre expressão | ✅ | contornável | ✅ | n/a |
| `uuid` nativo | ✅ | ❌ | ✅ | n/a |
| Custo parado | instância | instância | ≥ 0,5 ACU | **US$ 0** |
| Aderência ao domínio | **alta** | alta | alta | **baixa** |

## Recomendação

**PostgreSQL 17 em Amazon RDS.** O domínio é relacional em todos os eixos que
importam, e nenhuma alternativa oferecia vantagem que compensasse abrir mão de
FK e transação. O custo parado — a única fraqueza real — foi resolvido no nível
da arquitetura: o RDS vive na **camada efêmera**
([ADR-0006](../adr/0006-duas-camadas-de-terraform.md)) e só existe enquanto o
ambiente está no ar.

Configuração, diagrama ER, relacionamentos e os ajustes feitos no modelo estão
no [documento de modelo de dados](../banco-de-dados.md).

## Riscos aceitos

| Risco | Situação atual | O que mudaria em produção real |
|---|---|---|
| `multi_az = false` | falha de AZ derruba o banco | habilitar Multi-AZ |
| `backup_retention_period = 0` | sem point-in-time recovery | ≥ 7 dias e snapshot final no destroy |
| `max_connections` como teto | HPA ≤ 10 pods + pool baixo por container da Lambda | RDS Proxy antes de aumentar réplicas |
| Escrita não escala horizontalmente | irrelevante no volume atual | réplica de leitura para relatórios |
