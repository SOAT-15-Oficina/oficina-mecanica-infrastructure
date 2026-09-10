# ADR-0009 — JWT HS256 com segredo compartilhado

- **Estado:** Aceita
- **Data:** 2026-09-02
- **Relacionada:** [RFC-0003](../rfc/0003-estrategia-de-autenticacao.md), [ADR-0002](0002-comunicacao-sincrona-http.md)

## Contexto

A Lambda emite o token; o monolito, em outro repositório e outro runtime,
precisa aceitá-lo. Os dois precisam concordar sobre validade sem se chamarem —
uma chamada de validação por requisição adicionaria latência e um ponto de falha
a cada request protegido ([ADR-0002](0002-comunicacao-sincrona-http.md)).

## Decisão

**JWT assinado com HS256, segredo único guardado no Secrets Manager, emitido
pela Lambda e validado offline pelo monolito.**

Claims:

| Claim | Conteúdo |
|---|---|
| `user` | username |
| `role` | `admin` ou `employee` |
| `iat` | emissão |
| `exp` | emissão + 24h |

Validação no middleware do monolito, em ordem: presença do header
`Authorization`, formato `Bearer <token>`, **algoritmo é HMAC** (recusa `alg:
none` e recusa troca para RS256), assinatura, expiração, e presença não-vazia de
`user` e `role`. As claims vão para `c.Locals("token")`; `RequireRoles` decide
autorização a partir dali.

O segredo:

- é gerado pelo Terraform na camada persistente e guardado no Secrets Manager;
- chega à Lambda por variável de ambiente resolvida no init do container;
- chega ao pod por `Secret` do Kubernetes criado pelo Terraform;
- **nunca** aparece em código, em `.env` commitado ou em variável de repositório.

Um teste de contrato em cada repositório (`internal/auth/contract_test.go`, com
`testdata/token.golden`) garante que um token emitido pelo formato da Lambda
continua sendo aceito pelo monolito. Se um dos lados mudar as claims, o teste do
outro quebra no CI.

## Alternativas consideradas

**RS256 com par de chaves e JWKS.** Tecnicamente superior: só o emissor teria a
chave privada, e o validador buscaria a pública por URL. Custo: expor um
endpoint JWKS, implementar cache e rotação, e um ponto de falha de rede no
caminho de validação. Com **um** emissor e **um** validador, ambos sob o mesmo
Terraform, HS256 entrega a mesma garantia prática. Se aparecer um terceiro
serviço validando tokens, esta ADR deve ser substituída.

**Amazon Cognito.** Resolveria emissão, rotação, MFA e recuperação de senha, e é
o caminho que uma operação real seguiria. Descartada porque a fase exige uma
*function serverless* de autenticação escrita por nós — usar Cognito
esvaziaria o requisito.

**Sessão em servidor (cookie + store).** Exigiria estado compartilhado entre até
10 réplicas — Redis ou tabela de sessão. Adiciona infraestrutura para resolver
um problema que o token sem estado não tem.

**Autorizador Lambda no API Gateway.** Centralizaria a validação, mas
adicionaria uma invocação por requisição protegida e não dispensaria o segredo.
Registrada como evolução em [ADR-0003](0003-api-gateway-como-unica-porta-publica.md).

## Consequências

**Positivas**
- Validação local, sem I/O: nenhuma chamada de rede no caminho autenticado.
- O monolito não conhece a Lambda. Trocar o emissor não muda o validador.
- Sem estado de sessão: qualquer réplica atende qualquer requisição.

**Negativas**
- **Segredo simétrico em dois lugares.** Quem valida também pode emitir. Aceito
  porque ambos são componentes de confiança da mesma aplicação.
- **Não há revogação.** Um token vazado vale até `exp` — até 24h. Mitigação real
  exigiria lista de revogação com estado compartilhado; a mitigação atual é a
  janela curta e o fato de que a rota está atrás do gateway com throttling.
- Rotação do segredo invalida todos os tokens em circulação de uma vez.
- 24h é conveniente em uso interativo e generoso para produção; um sistema real
  usaria access token curto + refresh token.
