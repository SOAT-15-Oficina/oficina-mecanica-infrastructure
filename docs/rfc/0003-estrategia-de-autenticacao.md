# RFC-0003 — Estratégia de autenticação e autorização

- **Estado:** Aceita
- **Data:** 2026-09-02
- **Decisões derivadas:** [ADR-0009](../adr/0009-jwt-hs256-com-segredo-compartilhado.md), [ADR-0003](../adr/0003-api-gateway-como-unica-porta-publica.md)
- **Diagrama:** [sequência — autenticação](../diagramas/sequencia-autenticacao.md)

## Problema

O sistema tem **duas populações de usuário com necessidades opostas**:

1. **Operadores** (atendente, mecânico, administrador). Usam o painel todos os
   dias, executam operações destrutivas, precisam de identidade e de papel. São
   dezenas de pessoas, todas cadastradas.
2. **Clientes da oficina.** Aparecem uma ou duas vezes por ano para aprovar um
   orçamento e acompanhar o conserto. São milhares, não têm conta e não vão
   criar uma para clicar em "aprovar".

Uma estratégia única serviria mal aos dois. Exigir cadastro do cliente
derrubaria a taxa de aprovação; deixar operações administrativas sem
autenticação é inaceitável.

A fase acrescenta uma restrição: a autenticação deve morar numa **function
serverless** que valide o usuário contra a base e devolva um **JWT**.

## Requisitos

- Rotas sensíveis inacessíveis sem credencial válida.
- Autorização por papel: nem todo operador pode tudo.
- Emissão do token numa function serverless.
- Validação sem chamada de rede a cada requisição
  ([ADR-0002](../adr/0002-comunicacao-sincrona-http.md)).
- Segredo fora do código e fora de variável de repositório.
- Cliente final aprova orçamento **sem cadastro**.

## Alternativas para os operadores

### JWT emitido por Lambda, validado no monolito — **recomendado**

Lambda em Go atrás de `POST /auth/login`. Confere a senha com **argon2id** — os
parâmetros de custo são lidos do próprio hash gravado, então mudar o custo afeta
só senhas novas — e assina um JWT HS256 com `user`, `role`, `iat` e `exp` (+24h).

**A favor.** Atende ao requisito da fase, valida offline no monolito, sem estado
de sessão a compartilhar entre até 10 réplicas. `Register` e `Login` na mesma
função: duas Lambdas dobrariam infraestrutura e cold starts sem ganho.

**Contra.** Segredo simétrico conhecido pelos dois lados; sem revogação antes de
`exp`.

### Amazon Cognito

**A favor.** Resolve emissão, rotação, MFA, recuperação de senha e hosted UI. É
o que uma operação real usaria.

**Contra.** **Esvazia o requisito da fase** — não haveria function serverless de
autenticação escrita por nós. Adiciona um serviço a configurar e um vocabulário
(user pool, app client, fluxos OAuth) desproporcional para dois papéis.

### Autorizador Lambda no API Gateway

Um `REQUEST` authorizer validaria o token antes de qualquer integração.

**A favor.** Centraliza a validação; o monolito receberia identidade já
resolvida. Rota não autorizada nunca chega à VPC.

**Contra.** Uma invocação a mais por requisição protegida (latência e custo), e
o autorizador precisaria do mesmo segredo. Com **um** consumidor da API, o
middleware do monolito entrega a mesma garantia por zero. Registrado como
evolução natural em [ADR-0003](../adr/0003-api-gateway-como-unica-porta-publica.md).

### Sessão em servidor

Exigiria Redis ou tabela de sessão compartilhada entre réplicas — infraestrutura
nova para um problema que o token sem estado não tem.

## Autorização

Dois papéis, aplicados por middleware após a validação do token:

| Papel | Alcance |
|---|---|
| `admin` | tudo, incluindo `/users` (manutenção de operadores) |
| `employee` | clientes, veículos, catálogos, OS e itens de OS |

`/users` é a única família de rotas restrita a `admin`. Papel ausente ou vazio
no token é tratado como token inválido, não como "sem papel".

## O canal do cliente final

O cliente **não recebe token**. Ele acessa dois tipos de rota pública:

| Rota | Prova de posse |
|---|---|
| `GET /public/approvals/services/{wosId}/approve` (e reject, approve-all, reject-all) | conhecer o **UUID do item**, enviado apenas no e-mail do orçamento |
| `GET /public/work-orders/{code}?document=CPF` | conhecer o **código da OS** e o **documento do cliente** |

O modelo é *capability by obscurity com identificador não adivinhável* — a mesma
ideia de um link de redefinição de senha. UUID v4 tem 122 bits de entropia; não
se enumera. Foi um dos motivos de adotar UUID como chave primária: um inteiro
sequencial nessa URL permitiria a qualquer cliente aprovar a OS de outro trocando
o número.

A consulta pública responde **404 tanto para "não existe" quanto para "não é
seu"**, para não confirmar a existência de uma OS a quem não tem o documento.

### Riscos reconhecidos deste canal

| Risco | Situação | Mitigação possível |
|---|---|---|
| Link não expira | vale enquanto a OS aceitar decisão | token de uso único com validade |
| Aprovação por `GET` | pré-carregador de e-mail pode disparar | trocar por página de confirmação com `POST` |
| Encaminhar o e-mail transfere o poder de aprovar | aceito | idem |
| Enumeração de `code` + `document` | improvável, mas o par é menos entrópico que o UUID | throttling por IP no gateway (já há 100 rps global) |

São riscos **conhecidos e aceitos** para o escopo da fase, não descuidos. A
alternativa — exigir cadastro do cliente — trocaria um risco de segurança por
uma queda real na taxa de aprovação de orçamentos.

## Proteção do segredo

| Onde | Como |
|---|---|
| Origem | gerado pelo Terraform na camada persistente |
| Repouso | Secrets Manager |
| Lambda | variável de ambiente resolvida no init do container |
| Pod | `Secret` do Kubernetes criado pelo Terraform, via `envFrom` |
| Código | nunca |

Um teste de contrato em cada repositório, com token *golden* fixo, garante que
emissor e validador não divirjam sem que o CI perceba.

## Recomendação

**JWT HS256 emitido pela Lambda e validado no monolito**, com autorização por
papel em middleware, e canal público baseado em identificador não adivinhável
para o cliente final. Formalizado em
[ADR-0009](../adr/0009-jwt-hs256-com-segredo-compartilhado.md).

## Evolução

1. Autorizador Lambda no gateway, quando houver um segundo consumidor da API.
2. RS256 com JWKS, quando houver um segundo validador.
3. Access token curto + refresh token, no lugar das 24h atuais.
4. Link de aprovação de uso único com expiração.
