# Modelo de dados

Justificativa da escolha do banco, diagrama entidade-relacionamento, explicação
dos relacionamentos e registro dos ajustes feitos no modelo relacional.

A decisão de motor está formalizada na
[RFC-0002](rfc/0002-escolha-do-banco-de-dados.md); este documento é o retrato do
schema em vigor. **O schema é propriedade do `oficina-mecanica-monolith`** — as
migrations vivem em `database/migrations/` daquele repositório e são aplicadas
por um `Job` do pipeline. A Lambda de autenticação lê e escreve `users`, mas
nunca roda migration.

---

## 1. Por que um relacional gerenciado

O domínio é uma ordem de serviço: um agregado com composição fixa
(OS → serviços → insumos), dinheiro, e transições de estado que precisam ser
atômicas. Três propriedades pesaram mais que qualquer outra:

**Integridade referencial declarada no banco.** Um `work_order_service` órfão é
um orçamento errado enviado a um cliente. Com chave estrangeira, o banco recusa;
sem ela, a recusa depende de todo caminho de código lembrar de verificar. Há
onze `FOREIGN KEY` no schema, e nenhuma delas é decorativa.

**Transação multi-linha.** Aprovar um item recalcula o total da OS, pode
transicionar o status e pode disparar alerta de compra. São escritas em três
tabelas que precisam valer juntas ou não valer. Um banco de documentos resolveria
com um agregado único, mas o catálogo de serviços e o de insumos são
compartilhados entre OSs — modelá-los embutidos duplicaria dado mutável.

**Consultas analíticas sem pipeline.** Os dashboards exigidos (volume diário de
OS, tempo médio por status, taxa de erro) são `GROUP BY` sobre colunas de
timestamp que já existem. Em SQL são uma query; fora dele, seriam um processo de
agregação a manter.

Escolhido **PostgreSQL 17** em **RDS**. O gerenciamento (backup, patch, failover,
métricas) não é diferencial de uma oficina, e o requisito da fase pede banco
gerenciado. Os detalhes da comparação com MySQL, Aurora Serverless e DynamoDB
estão na [RFC-0002](rfc/0002-escolha-do-banco-de-dados.md).

### Configuração em vigor

| Item | Valor | Razão |
|---|---|---|
| Engine | PostgreSQL 17 | tipos ricos, índice sobre expressão, `DEFERRABLE` |
| Classe | `var.database_instance_class` | dimensionada por ambiente |
| Storage | gp3, 20 GB com autoscaling até 50 GB | evita `storage-full` sem pagar por espaço parado |
| Criptografia | em repouso, ativada | dado pessoal de cliente (nome, CPF, e-mail, telefone) |
| Acesso público | desabilitado | só de dentro da VPC — ver [ADR-0003](adr/0003-api-gateway-como-unica-porta-publica.md) |
| Multi-AZ | desabilitado | ambiente sob demanda; ver *Riscos* |
| Retenção de backup | 0 dia | idem |
| Credencial | Secrets Manager | nunca em variável de repositório |

---

## 2. Diagrama entidade-relacionamento

```mermaid
erDiagram
    USERS ||--o{ WORK_ORDERS : "abre"
    USERS ||--o{ WORK_ORDERS : "é técnico de"
    CUSTOMERS ||--o{ VEHICLES : possui
    CUSTOMERS ||--o{ WORK_ORDERS : "é titular de"
    VEHICLES ||--o{ WORK_ORDERS : "recebe"
    WORK_ORDERS ||--o{ WORK_ORDER_SERVICES : contém
    SERVICES ||--o{ WORK_ORDER_SERVICES : "é catalogado em"
    WORK_ORDER_SERVICES ||--o{ WORK_ORDER_SERVICE_SUPPLIES : consome
    SUPPLIES ||--o{ WORK_ORDER_SERVICE_SUPPLIES : "é catalogado em"

    USERS {
        uuid id PK
        varchar username UK "150, único"
        varchar password_hash "argon2id, 255"
        varchar role "admin | employee"
        timestamp created_at
        timestamp updated_at
    }

    CUSTOMERS {
        uuid id PK
        varchar name "150"
        varchar document UK "CPF ou CNPJ, único"
        varchar document_type "CPF | CNPJ"
        varchar phone "nulo"
        varchar email "nulo — destino das notificações"
        timestamp created_at
        timestamp updated_at
    }

    VEHICLES {
        uuid id PK
        uuid customer_id FK
        varchar license_plate UK "único"
        varchar brand
        varchar model
        int year
        timestamp created_at
        timestamp updated_at
    }

    SERVICES {
        uuid id PK
        varchar title UK "único por LOWER(title)"
        text description
        int price_cents "centavos, nunca float"
        int estimated_time_minutes
        boolean active "default true"
        timestamp created_at
        timestamp updated_at
    }

    SUPPLIES {
        uuid id PK
        varchar title
        varchar type
        int price_cents
        int stock_quantity "default 0"
        int minimum_stock "default 0"
        boolean active
        timestamp created_at
        timestamp updated_at
    }

    WORK_ORDERS {
        uuid id PK
        varchar code UK "código legível, único"
        varchar title
        text description
        uuid customer_id FK
        uuid vehicle_id FK
        uuid opened_by_user_id FK
        uuid assigned_technician_id FK "nulo"
        varchar status "máquina de estados"
        int total_estimated_price_cents
        timestamp received_at
        timestamp quote_sent_at "nulo"
        timestamp approved_at "nulo"
        timestamp started_at "nulo"
        timestamp finished_at "nulo"
        timestamp delivered_at "nulo"
        timestamp created_at
        timestamp updated_at
    }

    WORK_ORDER_SERVICES {
        uuid id PK
        uuid work_order_id FK
        uuid service_id FK
        varchar service_title_snapshot
        text service_description_snapshot
        int service_price_cents_snapshot
        int service_estimated_time_minutes_snapshot
        varchar approval_status "PENDENTE | APROVADO | REPROVADO"
        varchar status "PENDENTE | EM_EXECUCAO | FINALIZADO"
        timestamp started_at "nulo"
        timestamp finished_at "nulo"
        timestamp created_at
        timestamp updated_at
    }

    WORK_ORDER_SERVICE_SUPPLIES {
        uuid id PK
        uuid work_order_service_id FK
        uuid supply_id FK
        varchar supply_title_snapshot
        int supply_price_cents_snapshot
        int supply_quantity
        timestamp created_at
        timestamp updated_at
    }
```

---

## 3. Os relacionamentos, um a um

### `customers` 1—N `vehicles`
Um cliente tem zero ou mais veículos; um veículo pertence a exatamente um
cliente. A placa é única globalmente, não por cliente: placa é identidade
nacional do veículo, e duas linhas com a mesma placa significariam cadastro
duplicado. Índice em `customer_id` porque "veículos deste cliente" é a consulta
da tela de abertura de OS.

### `customers` 1—N `work_orders` e `vehicles` 1—N `work_orders`
A OS aponta para **os dois**, e não apenas para o veículo. É redundância
deliberada: sem `customer_id` na OS, descobrir o titular exigiria passar por
`vehicles` — e se o veículo for transferido de dono, o histórico da OS antiga
passaria a apontar para o dono novo. A OS guarda quem era o cliente **naquela**
entrada. A consistência entre os dois é responsabilidade da aplicação, que
valida que o veículo pertence ao cliente na criação.

### `users` 1—N `work_orders`, duas vezes
`opened_by_user_id` é obrigatório: toda OS tem um responsável pela abertura.
`assigned_technician_id` é nulo: a OS pode existir antes de haver mecânico
designado. São duas FKs para a mesma tabela, com significados distintos — por
isso duas colunas, não uma tabela de papéis.

### `work_orders` 1—N `work_order_services`
O coração do modelo. Cada linha é **um item do orçamento**: um serviço do
catálogo aplicado a esta OS, com preço congelado, estado de aprovação próprio e
estado de execução próprio.

Os dois estados são independentes de propósito:

| | `approval_status` | `status` |
|---|---|---|
| Quem muda | o cliente, pelo link do e-mail | o mecânico, pela API autenticada |
| Valores | `PENDENTE`, `APROVADO`, `REPROVADO` | `PENDENTE`, `EM_EXECUCAO`, `FINALIZADO` |
| Efeito na OS | quando todas decididas, promove a OS a `APROVADO` ou `CANCELADA` | alimenta o tempo por serviço |

Colapsar os dois em uma coluna tornaria impossível representar "aprovado pelo
cliente, ainda não iniciado pelo mecânico" — que é o estado normal de um item
recém-aprovado.

### `services` 1—N `work_order_services`
A FK para o catálogo existe para rastreabilidade e para relatórios por tipo de
serviço. O que é cobrado, porém, vem dos campos `*_snapshot` — ver
[ADR-0010](adr/0010-snapshot-de-precos-na-ordem-de-servico.md).

### `work_order_services` 1—N `work_order_service_supplies`
Insumos são consumidos **por serviço**, não pela OS: trocar óleo e alinhar
consomem peças diferentes, e o cliente pode aprovar só um dos dois. Índice
**único** em `(work_order_service_id, supply_id)`: o mesmo insumo não aparece
duas vezes no mesmo item — a quantidade vai em `supply_quantity`.

### `supplies` 1—N `work_order_service_supplies`
`stock_quantity` e `minimum_stock` moram no catálogo. Comparar o somatório de
`supply_quantity` dos itens aprovados contra `stock_quantity` é o que dispara o
**alerta de compra** e o acréscimo de dois dias no prazo estimado.

---

## 4. Ajustes feitos no modelo

### 4.1 Snapshot de preço e tempo nos itens da OS
`work_order_services` e `work_order_service_supplies` copiam título, preço e
tempo estimado do catálogo no momento em que o item entra na OS.

É desnormalização deliberada. A alternativa — ler sempre do catálogo — faria um
orçamento aprovado mudar de valor quando o catálogo fosse reajustado, o que é
inaceitável para um documento que o cliente já aprovou. Também permite alterar o
catálogo sem versionar nada. Racional completo em
[ADR-0010](adr/0010-snapshot-de-precos-na-ordem-de-servico.md).

### 4.2 Remoção de `work_order_service_status_history`
*(migration `20260505000002_drop_work_order_service_status_history.sql`)*

A tabela guardava uma linha por mudança de estado de item. Foi removida porque:

- **Não era lida.** Nenhuma consulta do sistema a usava; nenhuma tela a exibia.
- **Era redundante.** Os únicos instantes com significado — início e fim — já
  estão em `started_at` e `finished_at` do próprio item, e os da OS em
  `received_at`, `quote_sent_at`, `approved_at`, `started_at`, `finished_at`,
  `delivered_at`.
- **Custava escrita no caminho quente.** Cada transição virava um `INSERT`
  adicional dentro da mesma transação.

A métrica de **tempo médio por status** exigida no dashboard sai das colunas de
timestamp, sem a tabela. Se um dia for preciso auditar *quem* mudou o quê, o
caminho é log estruturado de evento de domínio
([ADR-0011](adr/0011-logs-estruturados-com-correlacao.md)), não uma tabela de
histórico que ninguém lê. A migration tem `Down` completo — a decisão é
reversível.

### 4.3 Unicidade de título de serviço, sem sensibilidade a caixa
*(migration `20260422000000_add_services_title_unique_index.sql`)*

```sql
CREATE UNIQUE INDEX idx_services_title_unique ON services (LOWER(title));
```

"Troca de óleo" e "TROCA DE ÓLEO" eram duas linhas do catálogo, com preços que
divergiam com o tempo. Um `UNIQUE` comum não resolveria — daí o índice sobre
expressão. Acompanham dois índices de leitura: `active` (a listagem padrão filtra
por serviço ativo) e `title` (busca).

### 4.4 Dinheiro em centavos, como inteiro
Toda coluna monetária é `int` com sufixo `_cents`. Nenhum `float` participa de
cálculo de valor; a formatação para reais acontece na borda, ao montar o e-mail
ou a resposta JSON.

### 4.5 Chaves primárias UUID
Geradas pela aplicação, não pelo banco. Dois motivos: os links de aprovação
enviados por e-mail carregam o UUID do item, e um inteiro sequencial ali seria
enumerável — qualquer cliente poderia aprovar a OS de outro trocando o número na
URL. Além disso, a aplicação conhece o id antes do `INSERT`, o que simplifica a
montagem de agregados.

Para o humano, `work_orders.code` é o identificador legível (`UNIQUE`, com
índice) — é ele que aparece na consulta pública de status.

### 4.6 Estratégia de índices
Além das PKs e uniques:

| Tabela | Índice | Consulta que atende |
|---|---|---|
| `vehicles` | `customer_id`, `license_plate` | veículos do cliente; busca por placa |
| `work_orders` | `code`, `customer_id`, `vehicle_id`, `status` | consulta pública; histórico; painel filtrado por status |
| `work_order_services` | `work_order_id`, `service_id`, `approval_status`, `status` | montagem do agregado; pendências de aprovação; fila de execução |
| `work_order_service_supplies` | `work_order_service_id`, `supply_id`, único em `(wos_id, supply_id)` | insumos do item; cálculo de falta de estoque |
| `services` | `LOWER(title)` único, `active`, `title` | catálogo |

### 4.7 Foreign keys `DEFERRABLE INITIALLY IMMEDIATE`
Todas as FKs são declaradas assim. O comportamento padrão continua sendo
verificação imediata; a declaração apenas deixa aberta a possibilidade de adiar
a checagem até o `COMMIT` numa transação específica — útil para carga em lote e
para o seed de dados de exemplo, sem afetar o caminho normal.

### 4.8 Migrations idempotentes
`CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS` e blocos
`DO $$ ... EXCEPTION WHEN duplicate_object THEN NULL; END $$` para constraints.
Aplicar duas vezes não quebra — o que importa porque o `Job` de migration pode
ser reexecutado após uma falha de rede no meio do rollout.

---

## 5. Riscos conhecidos

| Risco | Situação | Mitigação se for para produção real |
|---|---|---|
| `multi_az = false` | uma falha de AZ derruba o banco | habilitar Multi-AZ |
| `backup_retention_period = 0` | sem point-in-time recovery | ≥ 7 dias + snapshot final no destroy |
| Sem particionamento em `work_orders` | irrelevante no volume atual | particionar por `received_at` quando passar de milhões de linhas |

---

## 6. Como inspecionar

```bash
# local — sobe Postgres e aplica as migrations
cd oficina-mecanica-monolith
docker compose up -d
go run ./cmd/api migrate

# na nuvem — o RDS não é alcançável de fora; use um pod da própria VPC
kubectl -n "$KUBE_NAMESPACE" exec -it deploy/api -- sh
```

O endpoint do banco é publicado no SSM como
`/oficina-mecanica/<ambiente>/database_endpoint` e a credencial fica no Secrets
Manager.
