# RFC-0002. Escolha do banco de dados

**Aceita** · 2026-09-02 · Origina [ADR-0005](../adr/0005-migrations-como-job-do-pipeline.md),
[ADR-0010](../adr/0010-snapshot-de-precos-na-ordem-de-servico.md) · Detalhamento no [modelo de dados](../banco-de-dados.md)

**Problema.** O desafio exige banco gerenciado e justificativa formal da
escolha, somada a ajustes documentados no modelo relacional. O domínio é uma
ordem de serviço de oficina: cliente, veículo, catálogo de serviços, catálogo
de insumos, e a OS que amarra tudo com estado, aprovação do cliente e dinheiro.

## O que o domínio exige

| Exigência | Por quê |
|---|---|
| Integridade referencial no banco | um `work_order_service` órfão é um orçamento errado enviado a um cliente real. O schema tem onze `FOREIGN KEY`, todas em uso |
| Transação multi-linha | aprovar um item recalcula o total, pode transicionar o status e pode disparar alerta de compra: escritas em três tabelas que valem juntas ou não valem |
| Consulta analítica sem pipeline | volume diário de OS, tempo médio por status e taxa de erro são `GROUP BY` sobre colunas de timestamp que já existem |
| Escrita modesta, leitura irregular | dezenas de OS por dia; o pico é de leitura, quando um lote de orçamentos é enviado e os clientes clicam quase ao mesmo tempo |
| Dado pessoal | nome, CPF ou CNPJ, e-mail e telefone: criptografia em repouso e ausência de acesso público não são opcionais |

## Alternativas

| Opção | A favor | Contra |
|---|---|---|
| **PostgreSQL no RDS** (recomendado) | integridade e transação como padrão; índice sobre expressão resolve duplicidade de título por caixa sem coluna extra nem trigger; `DEFERRABLE` nas FKs; `uuid` nativo e `jsonb` disponível; driver `pgx` maduro com pool; provider Terraform simples | instância cobra por hora ligada; escalar escrita é vertical; pool por processo multiplica conexões, e `max_connections` é teto real com a Lambda e até 10 pods |
| MySQL no RDS | igualmente gerenciado e barato, com FKs e transações no InnoDB | sem índice sobre expressão até 8.0.13 e, depois, com comportamento menos direto; sem `uuid` nativo; menos confortável em consulta analítica |
| Aurora Serverless v2 | escala automática, compatível com PostgreSQL | o piso de 0,5 ACU cobra mesmo ocioso, e a ACU custa mais que a instância `t`; com o ambiente subindo e descendo, a elasticidade não é aproveitada; bring-up mais lento |
| DynamoDB | cobrança por uso e US$ 0 parado; escala sem operação | sem junção, sem FK e sem transação multi-item barata; catálogo compartilhado entre OSs não pode ser embutido sem duplicar dado mutável; os `GROUP BY` dos dashboards virariam GSIs ou pipeline de agregação |
| PostgreSQL em contêiner no EKS | custo marginal zero | viola o requisito de banco gerenciado; estado em Kubernetes exige `StatefulSet`, PVC, backup e plano de recuperação |

## Comparação

| | PostgreSQL RDS | MySQL RDS | Aurora Sv2 | DynamoDB |
|---|---|---|---|---|
| Integridade referencial | sim | sim | sim | não |
| Transação multi-tabela | sim | sim | sim | limitada e cara |
| Analítica sem pipeline | sim | parcial | sim | não |
| Índice sobre expressão | sim | contornável | sim | não se aplica |
| `uuid` nativo | sim | não | sim | não se aplica |
| Custo parado | instância | instância | 0,5 ACU ou mais | **US$ 0** |
| Aderência ao domínio | **alta** | alta | alta | **baixa** |

**Recomendação.** PostgreSQL 17 em Amazon RDS. O domínio é relacional em todos
os eixos que importam, e nenhuma alternativa oferece vantagem que compense
abrir mão de FK e transação. O custo parado, única fraqueza real, foi resolvido
na arquitetura: o RDS vive na camada efêmera ([ADR-0006](../adr/0006-duas-camadas-de-terraform.md)) e só
existe enquanto o ambiente está no ar.

## Riscos aceitos

| Risco | Situação atual | Em produção real |
|---|---|---|
| `multi_az = false` | falha de AZ derruba o banco | habilitar Multi-AZ |
| `backup_retention_period = 0` | sem point-in-time recovery | 7 dias ou mais, e snapshot final no destroy |
| `max_connections` como teto | HPA até 10 pods, mais pool baixo por container da Lambda | RDS Proxy antes de aumentar réplicas |
| Escrita não escala horizontalmente | irrelevante no volume atual | réplica de leitura para relatórios |
