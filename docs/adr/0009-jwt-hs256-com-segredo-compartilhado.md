# ADR-0009. JWT HS256 com segredo compartilhado

**Aceita** · 2026-09-02 · Relacionada [RFC-0003](../rfc/0003-estrategia-de-autenticacao.md),
[ADR-0002](./0002-comunicacao-sincrona-http.md)

**Contexto.** A Lambda emite o token, e o monolito, em outro repositório e
outro runtime, precisa aceitá-lo. Os dois precisam concordar sobre validade sem
se chamarem, porque uma chamada de validação por requisição adicionaria
latência e um ponto de falha a cada request protegido
([ADR-0002](./0002-comunicacao-sincrona-http.md)).

**Decisão.** JWT assinado com HS256, com segredo único no Secrets Manager,
emitido pela Lambda e validado offline pelo monolito.

| Claim | Conteúdo |
|---|---|
| `user` | username |
| `role` | `admin` ou `employee` |
| `iat` | emissão |
| `exp` | emissão mais 24 horas |

Validação no middleware, nesta ordem: presença do header `Authorization`;
formato `Bearer <token>`; **algoritmo é HMAC**, o que recusa `alg: none` e
recusa troca para RS256; assinatura; expiração; e presença não vazia de `user`
e `role`. As claims vão para `c.Locals("token")`, e `RequireRoles` decide
autorização a partir dali.

O segredo é gerado pelo Terraform na camada persistente e guardado no Secrets
Manager; chega à Lambda por variável de ambiente resolvida no init do
container; chega ao pod por `Secret` do Kubernetes criado pelo Terraform; e
**nunca** aparece em código, em `.env` commitado ou em variável de repositório.

Um teste de contrato em cada repositório (`internal/auth/contract_test.go`, com
`testdata/token.golden`) garante que um token emitido no formato da Lambda
continua sendo aceito pelo monolito. Se um dos lados mudar as claims, o teste do
outro falha no CI.

## Alternativas descartadas

| Opção | Motivo do descarte |
|---|---|
| RS256 com par de chaves e JWKS | tecnicamente superior, mas exigiria expor um endpoint JWKS, implementar cache e rotação, e introduzir falha de rede no caminho de validação. Com um emissor e um validador sob o mesmo Terraform, HS256 entrega a mesma garantia prática. **Se aparecer um terceiro serviço validando tokens, esta ADR deve ser substituída** |
| Amazon Cognito | resolveria emissão, rotação, MFA e recuperação de senha, e é o caminho de uma operação real, mas o desafio exige uma function serverless de autenticação implementada no projeto |
| Sessão em servidor | exigiria estado compartilhado entre até 10 réplicas, em Redis ou tabela de sessão |
| Autorizador Lambda no gateway | centralizaria a validação, mas adicionaria uma invocação por requisição protegida e não dispensaria o segredo. Registrada como evolução em [ADR-0003](./0003-api-gateway-como-unica-porta-publica.md) |

## Consequências

| Ganhos | Custos |
|---|---|
| Validação local, sem I/O: nenhuma chamada de rede no caminho autenticado | **segredo simétrico em dois lugares**: quem valida também pode emitir. Aceito porque ambos são componentes de confiança da mesma aplicação |
| O monolito não conhece a Lambda: trocar o emissor não muda o validador | **não há revogação**: um token vazado vale até `exp`, até 24 horas. Mitigação atual é a janela curta e o throttling no gateway |
| Sem estado de sessão: qualquer réplica atende qualquer requisição | rotação do segredo invalida todos os tokens em circulação de uma vez |
| | 24 horas é generoso para produção: um sistema real usaria access token curto mais refresh token |
