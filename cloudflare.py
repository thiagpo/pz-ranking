# -*- coding: utf-8 -*-
"""
Publica o ranking em pz.simpless.com.br (Cloudflare Worker + KV, plano gratuito).

Antes da primeira vez, logue na Cloudflare (abre o navegador):  npx wrangler login
Primeira vez:                      py -3 cloudflare.py configurar
Quando o layout da pagina mudar:   py -3 cloudflare.py publicar

Os dados em si sao enviados pelo atualiza_ranking.py (GitHub Actions ou local).
"""
import os, re, sys, json, secrets, shutil, subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
CF = os.path.join(AQUI, "cloudflare")
TOML = os.path.join(CF, "wrangler.toml")
PUBLIC = os.path.join(CF, "public")
SEGREDOS = os.path.join(AQUI, "segredos.json")
DOMINIO = "https://pz.simpless.com.br"


def run(cmd, **kw):
    print(">", cmd, flush=True)
    return subprocess.run(cmd, shell=True, cwd=CF, text=True, encoding="utf-8", errors="replace", **kw)


def publicar():
    os.makedirs(PUBLIC, exist_ok=True)
    shutil.copy(os.path.join(AQUI, "ranking.html"), os.path.join(PUBLIC, "index.html"))
    r = run("npx --yes wrangler deploy")
    if r.returncode:
        sys.exit("deploy falhou")
    print("publicado em", DOMINIO)


def configurar():
    toml = open(TOML, encoding="utf-8").read()
    if "KV_ID_AQUI" in toml:
        r = run("npx --yes wrangler kv namespace create DADOS", capture_output=True)
        print(r.stdout or "", r.stderr or "")
        m = re.search(r'id\s*=\s*"([0-9a-f]{32})"', (r.stdout or "") + (r.stderr or ""))
        if not m:
            sys.exit("nao achei o id do KV na saida acima (esta logado? rode: npx wrangler login)")
        open(TOML, "w", encoding="utf-8").write(toml.replace("KV_ID_AQUI", m.group(1)))
    seg = json.load(open(SEGREDOS, encoding="utf-8")) if os.path.exists(SEGREDOS) else {}
    token = seg.get("PZ_UPLOAD_TOKEN") or secrets.token_urlsafe(32)
    seg["PZ_UPLOAD_TOKEN"] = token
    json.dump(seg, open(SEGREDOS, "w", encoding="utf-8"), indent=2)
    r = run("npx --yes wrangler secret put UPLOAD_TOKEN", input=token + "\n")
    if r.returncode:
        sys.exit("nao consegui gravar o segredo no Worker")
    publicar()
    r = run(f'py -3 "{os.path.join(AQUI, "atualiza_ranking.py")}" --sem-download')
    print("\nPronto. Pagina:", DOMINIO)
    print("Token de envio (secret PZ_UPLOAD_TOKEN no GitHub):", token)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "publicar"
    {"configurar": configurar, "publicar": publicar}[cmd]()
