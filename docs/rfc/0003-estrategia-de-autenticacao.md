# RFC-0003. Estratégia de autenticação e autorização

**Aceita** · 2026-09-02 · Origina [ADR-0003](../adr/0003-api-gateway-como-unica-porta-publica.md),
[ADR-0009](../adr/0009-jwt-hs256-com-segredo-compartilhado.md) · Diagramas no [sequência de autenticação](../diagramas/sequencia-autenticacao.md)

**Problema.** Duas populações de usuário com necessidades opostas. Operadores
(atendente, mecânico, administrador) usam o painel todos os dias, executam
operações destrutivas e precisam de identidade e papel: são dezenas, todos
cadastrados. Clientes da oficina aparecem uma ou duas vezes por ano para
aprovar um orçamento: são milhares, não têm conta e não vão criar uma para
clicar em "aprovar".

Exigir cadastro do cliente derrubaria a taxa de aprovação; deixar operações
administrativas sem autenticação é inaceitável. O desafio acrescenta uma
restrição: a autenticação deve morar em uma **function serverless** que valide
o usuário contra a base e devolva um **JWT**.

**Requisitos.** Rotas sensíveis inacessíveis sem credencial válida; autorização
por papel; emissão do token em function serverless; validação sem chamada de
rede por requisição ([ADR-0002](../adr/0002-comunicacao-sincrona-http.md)); segredo fora do código e de
variável de repositório; cliente final aprova sem cadastro.

## Alternativas para os operadores

| Opção | A favor | Contra |
|---|---|---|
| **JWT emitido por Lambda, validado no monolito** (recomendado) | atende ao requisito; valida offline, sem estado de sessão entre até 10 réplicas; `Register` e `Login` na mesma função, porque duas Lambdas dobrariam infraestrutura e cold starts sem ganho | segredo simétrico conhecido pelos dois lados; sem revogação antes de `exp` |
| Amazon Cognito | resolve emissão, rotação, MFA, recuperação de senha e hosted UI; é o que uma operação real usaria | não atende ao requisito de function serverless implementada no projeto; adiciona serviço e vocabulário desproporcionais para dois papéis |
| Autorizador Lambda no API Gateway | centraliza a validação; rota não autorizada nunca chega à VPC | uma invocação a mais por requisição protegida, e o autorizador precisaria do mesmo segredo. Com um consumidor, o middleware entrega a mesma garantia. Registrado como evolução em [ADR-0003](../adr/0003-api-gateway-como-unica-porta-publica.md) |
| Sessão em servidor | modelo familiar | exigiria Redis ou tabela de sessão compartilhada entre réplicas: infraestrutura nova para um problema que o token sem estado não tem |

A Lambda confere a senha com **argon2id**, lendo os parâmetros de custo do
próprio hash gravado, o que faz uma mudança de custo afetar só senhas novas, e
assina um JWT HS256 com `user`, `role`, `iat` e `exp` de 24 horas.

## Autorização

| Papel | Alcance |
|---|---|
| `admin` | tudo, incluindo `/users` (manutenção de operadores) |
| `employee` | clientes, veículos, catálogos, OS e itens de OS |

`/users` é a única família de rotas restrita a `admin`. Papel ausente ou vazio
no token é tratado como token inválido, e não como ausência de papel.

## O canal do cliente final

O cliente não recebe token. Acessa duas rotas públicas:

| Rota | Prova de posse |
|---|---|
| `GET /public/approvals/services/{wosId}/approve`, e as variantes reject, approve-all e reject-all | conhecer o **UUID do item**, enviado apenas no e-mail do orçamento |
| `GET /public/work-orders/{code}?document=CPF` | conhecer o **código da OS** e o **documento do cliente** |

O modelo é *capability* por identificador não adivinhável, o mesmo mecanismo de
um link de redefinição de senha. UUID v4 tem 122 bits de entropia e não é
enumerável. Foi um dos motivos de adotar UUID como chave primária: um inteiro
sequencial nessa URL permitiria a qualquer cliente aprovar a OS de outro
trocando o número. A consulta pública responde **404 tanto para "não existe"
quanto para "não é seu"**, para não confirmar a existência de uma OS a quem não
tem o documento.

| Risco do canal | Situação | Mitigação possível |
|---|---|---|
| Link não expira | vale enquanto a OS aceitar decisão | token de uso único com validade |
| Aprovação por `GET` | pré-carregador de e-mail pode disparar | página de confirmação com `POST` |
| Encaminhar o e-mail transfere o poder de aprovar | aceito | idem |
| Enumeração de `code` mais `document` | par menos entrópico que o UUID | throttling por IP no gateway, já limitado a 100 rps |

Riscos conhecidos e aceitos para o escopo atual. A alternativa, exigir cadastro
do cliente, trocaria um risco de segurança por uma queda real na taxa de
aprovação de orçamentos.

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

**Recomendação.** JWT HS256 emitido pela Lambda e validado no monolito, com
autorização por papel em middleware e canal público por identificador não
adivinhável. Formalizado em [ADR-0009](../adr/0009-jwt-hs256-com-segredo-compartilhado.md).

**Evolução.** Autorizador no gateway quando houver um segundo consumidor;
RS256 com JWKS quando houver um segundo validador; access token curto mais
refresh token no lugar das 24 horas; link de aprovação de uso único.
