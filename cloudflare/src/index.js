// Worker do Ranking Base dos Bagres.
// GET /            -> index.html com o data.json mais recente ja embutido
// GET /data.json   -> dados atuais (a pagina busca isso a cada minuto)
// PUT /data.json   -> o script atualiza_ranking.py envia os dados (Authorization: Bearer UPLOAD_TOKEN)
export default {
  async fetch(req, env) {
    const url = new URL(req.url);

    if (url.pathname === '/data.json') {
      if (req.method === 'PUT') {
        const auth = req.headers.get('authorization') || '';
        if (!env.UPLOAD_TOKEN || auth !== 'Bearer ' + env.UPLOAD_TOKEN) return new Response('nao autorizado', { status: 401 });
        const body = await req.text();
        try { JSON.parse(body); } catch { return new Response('json invalido', { status: 400 }); }
        await env.DADOS.put('data', body);
        return new Response('ok');
      }
      const d = await env.DADOS.get('data');
      return new Response(d || '{}', {
        status: d ? 200 : 404,
        headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', 'access-control-allow-origin': '*' }
      });
    }

    if (url.pathname === '/' || url.pathname === '/index.html') {
      const res = await env.ASSETS.fetch(new Request(new URL('/index.html', req.url), req));
      const d = await env.DADOS.get('data');
      if (!d) return res;
      const html = await res.text();
      const fresh = html.replace(/<script id="data" type="application\/json">[\s\S]*?<\/script>/,
        () => '<script id="data" type="application/json">' + d.replace(/<\//g, '<\\/') + '</script>');
      return new Response(fresh, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });
    }

    return env.ASSETS.fetch(req);
  }
};
