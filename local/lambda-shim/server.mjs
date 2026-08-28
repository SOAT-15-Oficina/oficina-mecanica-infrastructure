// Adaptador HTTP -> Lambda para o ambiente local.
//
// O Lambda Runtime Interface Emulator nao fala HTTP comum: ele espera um POST
// em /2015-03-31/functions/function/invocations com um EVENTO no corpo. Na AWS
// quem constroi esse evento e o API Gateway.
//
// Este shim faz o mesmo papel localmente: recebe uma requisicao HTTP normal,
// monta um APIGatewayV2HTTPRequest com a routeKey que a funcao espera, invoca o
// RIE e devolve a resposta ao cliente. ~60 linhas, sem dependencias.
import http from 'node:http';

const RIE_URL = process.env.RIE_URL ?? 'http://lambda:8080/2015-03-31/functions/function/invocations';
const PORT = Number(process.env.PORT ?? 8080);

// Precisa espelhar as rotas declaradas em ephemeral/apigateway_routes.tf.
const ROUTES = new Set(['POST /auth/login', 'POST /auth/register']);

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://local');
    const routeKey = `${req.method} ${url.pathname}`;
    const body = await readBody(req);

    const event = {
      version: '2.0',
      routeKey: ROUTES.has(routeKey) ? routeKey : '$default',
      rawPath: url.pathname,
      rawQueryString: url.search.replace(/^\?/, ''),
      headers: req.headers,
      body,
      isBase64Encoded: false,
      requestContext: {
        http: { method: req.method, path: url.pathname },
      },
    };

    const upstream = await fetch(RIE_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(event),
    });

    const payload = await upstream.json();

    // Erro do proprio runtime (funcao lancou), nao resposta da aplicacao.
    if (payload.errorMessage) {
      res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'lambda error', detail: payload.errorMessage }));
      return;
    }

    res.writeHead(payload.statusCode ?? 200, payload.headers ?? { 'Content-Type': 'application/json' });
    res.end(payload.body ?? '');
  } catch (err) {
    res.writeHead(502, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'shim failure', detail: String(err) }));
  }
});

server.listen(PORT, () => {
  console.log(`lambda-shim ouvindo em :${PORT} -> ${RIE_URL}`);
});
