# -*- coding: utf-8 -*-
"""
Atualiza o Ranking Base dos Bagres.

Como usar (PowerShell ou Prompt):
    py -3 C:\\Users\\am-ap\\Zomboid\\ranking\\atualiza_ranking.py
    py -3 atualiza_ranking.py --sem-download   (so regenera com os dados ja baixados)

O que faz:
  1. Conecta no SFTP da RazeHost e baixa: arquivos do mod TwisTonFire Stats, todos os PerkLog,
     o log de conexoes atual (quem esta online) e o banco players.db (profissao e traits).
  2. Gera data.json (dados puros) e ranking.html (pagina com os dados embutidos).
  3. Se HOSPEDAGEM estiver preenchido, envia os dois arquivos para o seu site.

Requisito: Python 3 com paramiko (pip install paramiko).
Para rodar sozinho, crie uma tarefa no Agendador de Tarefas do Windows (a cada 5 ou 10 min).
"""
import os, re, io, json, glob, datetime, collections, posixpath, sys, sqlite3

# ---------------- CONFIGURACAO ----------------
# Segredos: variaveis de ambiente (GitHub Actions) ou segredos.json ao lado deste arquivo (uso local, fora do git).
_AQUI = os.path.dirname(os.path.abspath(__file__))
_SEG = json.load(open(os.path.join(_AQUI, "segredos.json"), encoding="utf-8")) if os.path.exists(os.path.join(_AQUI, "segredos.json")) else {}
def segredo(nome): return os.environ.get(nome) or _SEG.get(nome, "")

SERVIDOR = dict(host="sp3.razehost.com.br", port=2031,
                user="thiagoifnmg8am.2fecdaf4", password=segredo("PZ_SFTP_PASSWORD"))
REMOTO_STATS = ".cache/Lua/ttf_stats_mp"
REMOTO_LOGS  = ".cache/Logs"
REMOTO_PLAYERS_DB = ".cache/Saves/Multiplayer/RazeHost/players.db"
INFO_SERVIDOR = dict(nome="Base dos Bagres", versao="42.21", pop="16x", ip="45.146.81.10", porta="16266")
REMOTO_SANDBOX = ".cache/Server/RazeHost_SandboxVars.lua"
REMOTO_INI = ".cache/Server/RazeHost.ini"

# Mortes que NAO contam (evento do helicoptero de 24/10, em UTC).
JANELAS_IGNORADAS = [("2026-10-24 16:20:00", "2026-10-24 18:10:00")]

# Opcional: envio automatico. Deixe host="" (ou url="") para nao enviar.
#   tipo "sftp"/"ftp": host, port, user, password, pasta (onde ficam index.html e data.json)
#   tipo "supabase":   url (https://xxxx.supabase.co), key (service_role), bucket (publico), pasta
#   tipo "worker":     url (https://pz.simpless.com.br), token (segredo PZ_UPLOAD_TOKEN)
HOSPEDAGEM = dict(tipo="worker", url="https://pz.simpless.com.br", token=segredo("PZ_UPLOAD_TOKEN"),
                  host="", port=22, user="", password="", pasta="", key="", bucket="")
# -----------------------------------------------

AQUI = os.path.dirname(os.path.abspath(__file__))
DADOS = os.path.join(AQUI, "dados")
os.makedirs(DADOS, exist_ok=True)


def baixar():
    import paramiko
    t = paramiko.Transport((SERVIDOR["host"], SERVIDOR["port"]))
    t.connect(username=SERVIDOR["user"], password=SERVIDOR["password"])
    sftp = paramiko.SFTPClient.from_transport(t)
    n = 0
    for f in glob.glob(os.path.join(DADOS, "stats__*.txt")):
        os.remove(f)   # arquivos apagados no servidor nao devem sobrar aqui
    for f in sftp.listdir(REMOTO_STATS):
        if f.endswith(".txt"):
            sftp.get(posixpath.join(REMOTO_STATS, f), os.path.join(DADOS, "stats__" + f)); n += 1

    def walk(d):
        for e in sftp.listdir_attr(d):
            p = posixpath.join(d, e.filename)
            if e.longname.startswith("d"):
                yield from walk(p)
            elif e.filename.endswith("_PerkLog.txt"):
                yield p
    for p in walk(REMOTO_LOGS):
        nome = "perklog__" + p.replace(REMOTO_LOGS + "/", "").replace("/", "__")
        sftp.get(p, os.path.join(DADOS, nome)); n += 1

    # log de conexoes da sessao atual (fica na raiz de Logs)
    for f in glob.glob(os.path.join(DADOS, "user__*.txt")):
        os.remove(f)
    atuais = sorted(f for f in sftp.listdir(REMOTO_LOGS) if f.endswith("_user.txt"))
    if atuais:
        sftp.get(posixpath.join(REMOTO_LOGS, atuais[-1]), os.path.join(DADOS, "user__" + atuais[-1])); n += 1

    try:
        sftp.get(REMOTO_PLAYERS_DB, os.path.join(DADOS, "players.db")); n += 1
    except IOError as e:
        print("players.db nao baixado:", e)
    sftp.get(REMOTO_SANDBOX, os.path.join(DADOS, "sandbox.lua")); sftp.get(REMOTO_INI, os.path.join(DADOS, "server.ini")); n += 2
    sftp.close(); t.close()
    print(f"baixados {n} arquivos")


def plist(v):
    d = {}
    for it in (v or "").split("|"):
        if ":" in it:
            k, n = it.rsplit(":", 1)
            try: d[k] = d.get(k, 0) + int(float(n))
            except ValueError: pass
    return d


def series(v):
    out = []
    for it in (v or "").split("|"):
        f = it.split(",")
        if len(f) >= 2:
            try: out.append([int(float(f[0])), int(float(f[1]))])
            except ValueError: pass
    return out


def ler_traits(dic):
    """Profissao e traits do personagem atual de cada jogador, lidos do players.db."""
    out = {}
    p = os.path.join(DADOS, "players.db")
    if not os.path.exists(p):
        return out
    try:
        c = sqlite3.connect(p)
        for user, name, dead, blob in c.execute("select username, name, isDead, data from networkPlayers"):
            toks = list(dict.fromkeys(t.decode() for t in re.findall(rb"base:[A-Za-z0-9_]+", blob or b"")))
            prof = next((t for t in toks if t in dic["profs"]), "")
            traits = [t for t in toks if t in dic["traits"]]
            favs = list(dict.fromkeys(f.decode("utf-8", "ignore")[4:] for f in re.findall(rb"Fav:[^\x00-\x1f]{2,40}", blob or b"")))
            out[user] = {"prof": prof, "traits": traits, "favs": favs, "charName": (name or "").strip(), "dbDead": bool(dead)}
        c.close()
    except Exception as e:
        print("erro lendo players.db:", e)
    return out


def ler_online():
    online = set()
    for f in sorted(glob.glob(os.path.join(DADOS, "user__*.txt"))):
        for line in open(f, encoding="utf-8", errors="ignore"):
            m = re.search(r'"([^"]+)" fully connected', line)
            if m: online.add(m.group(1)); continue
            m = re.search(r'"([^"]+)" disconnected player', line)
            if m: online.discard(m.group(1))
    return sorted(online)


INI_PUBLICO = ["PVP", "PauseEmpty", "GlobalChat", "Open", "SafetySystem", "Map", "Public", "PublicName", "MaxPlayers",
               "SafehousePreventsLootRespawn", "DropOffWhiteListAfterDeath", "NoFire", "AnnounceDeath", "SaveWorldEveryMinutes",
               "PlayerSafehouse", "AdminSafehouse", "SafehouseAllowTrepass", "SafehouseAllowFire", "SafehouseAllowLoot",
               "SafehouseAllowRespawn", "SafehouseDaySurvivedToClaim", "AllowDestructionBySledgehammer", "SleepAllowed", "SleepNeeded",
               "KnockedDownAllowed", "SneakModeHideFromOtherPlayers", "SpeedLimit", "PlayerRespawnWithSelf", "PlayerRespawnWithOther",
               "FastForwardMultiplier", "Faction", "FactionDaySurvivedToCreate", "VoiceEnable", "Voice3D", "PerkLogs", "SteamVAC",
               "PlayerBumpPlayer", "HidePlayersBehindYou", "MapRemotePlayerVisibility", "DisableVehicleTowing", "DisableTrailerTowing",
               "BackupsCount", "ServerWelcomeMessage", "AllowCoop", "PVPMeleeDamageModifier", "PVPFirearmDamageModifier"]


def ler_sandbox():
    """Le SandboxVars.lua: valores (com prefixo de tabela, ex. ZombieLore.Speed) e, dos comentarios, descricao e opcoes."""
    p = os.path.join(DADOS, "sandbox.lua")
    vals, meta = {}, {}
    if not os.path.exists(p):
        return vals, meta
    stack = []; desc = None; opts = {}
    for raw in open(p, encoding="utf-8", errors="ignore"):
        line = raw.strip()
        if not line:
            continue
        if line.startswith("--"):
            c = line[2:].strip()
            m = re.match(r"^(\d+)\s*=\s*(.+)$", c)
            if m: opts[int(m.group(1))] = m.group(2).strip()
            elif desc is None: desc = c
            continue
        m = re.match(r"^(\w+)\s*=\s*\{", line)
        if m:
            stack.append(m.group(1)); desc = None; opts = {}; continue
        if line.startswith("}"):
            if stack: stack.pop()
            continue
        m = re.match(r"^(\w+)\s*=\s*(.+?),?$", line)
        if m:
            k, v = m.group(1), m.group(2).strip()
            key = ".".join(stack[1:] + [k]) if len(stack) > 1 else k
            if v in ("true", "false"): val = (v == "true")
            elif v.startswith('"'): val = v.strip('"')
            else:
                try: val = float(v) if "." in v else int(v)
                except ValueError: val = v
            vals[key] = val
            if desc or opts: meta[key] = {"desc": desc or "", "opts": {str(a): b for a, b in opts.items()}}
            desc = None; opts = {}
    return vals, meta


def ler_ini():
    p = os.path.join(DADOS, "server.ini")
    out = {}
    if not os.path.exists(p):
        return out, [], []
    mods, ws = [], []
    for raw in open(p, encoding="utf-8", errors="ignore"):
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        if k == "Mods": mods = [x for x in v.split(";") if x]
        elif k == "WorkshopItems": ws = [x for x in v.split(";") if x]
        elif k in INI_PUBLICO:
            out[k] = (v == "true") if v in ("true", "false") else v
    return out, mods, ws


def ler_mods(ws):
    """Titulo dos mods da Workshop (cache em mods_cache.json; busca na API da Steam so os que faltam)."""
    cpath = os.path.join(AQUI, "mods_cache.json")
    cache = json.load(open(cpath, encoding="utf-8")) if os.path.exists(cpath) else {}
    falta = [i for i in ws if i not in cache]
    if falta:
        try:
            import urllib.request, urllib.parse
            d = {"itemcount": len(falta)}
            for i, x in enumerate(falta): d[f"publishedfileids[{i}]"] = x
            req = urllib.request.Request("https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/",
                                         data=urllib.parse.urlencode(d).encode(), headers={"User-Agent": "Mozilla/5.0"})
            j = json.loads(urllib.request.urlopen(req, timeout=30).read())
            for it in j["response"]["publishedfiledetails"]:
                cache[it["publishedfileid"]] = {"title": it.get("title", "?"), "updated": it.get("time_updated", 0)}
            json.dump(cache, open(cpath, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
        except Exception as e:
            print("titulos de mods nao atualizados:", e)
    return [{"id": i, "title": cache.get(i, {}).get("title", i), "updated": cache.get(i, {}).get("updated", 0)} for i in ws]


def montar():
    dpath = os.path.join(AQUI, "dicionario.json")
    dic = json.load(open(dpath, encoding="utf-8")) if os.path.exists(dpath) else {"traits": {}, "profs": {}}

    chars = {}
    for f in glob.glob(os.path.join(DADOS, "stats__*.txt")):
        if f.endswith("index.txt"):
            continue
        kv = {}
        for line in open(f, encoding="utf-8", errors="ignore"):
            line = line.rstrip("\n")
            if "=" in line:
                k, v = line.split("=", 1); kv[k] = v
        if kv.get("deleted") == "true" or "characterID" not in kv:
            continue
        chars[kv["characterID"]] = kv

    deaths = collections.defaultdict(list); hours_alive = {}; login_ts = {}
    best = collections.defaultdict(dict); cur = {}; cur_ts = {}
    last_seen = {}; first_seen = {}
    rx = re.compile(r"^\[(\d\d)-(\d\d)-(\d\d) (\d\d:\d\d:\d\d)[^\]]*\] \[(\d+)\]\[([^\]]*)\]\[([^\]]*)\]\[([^\]]*)\](.*)$")
    for f in sorted(glob.glob(os.path.join(DADOS, "perklog__*.txt"))):
        for line in open(f, encoding="utf-8", errors="ignore"):
            m = rx.match(line.strip())
            if not m:
                continue
            dd, mm, yy, t, sid, user, pos, ev, rest = m.groups()
            ts = f"20{yy}-{mm}-{dd} {t}"
            hs = re.search(r"Hours Survived: (\d+)", rest)
            last_seen[user] = max(last_seen.get(user, ts), ts); first_seen[user] = min(first_seen.get(user, ts), ts)
            if ev == "Died":
                h = int(hs.group(1)) if hs else 0
                ignorada = any(a <= ts <= b for a, b in JANELAS_IGNORADAS)
                if h > 0 and not ignorada:
                    deaths[user].append({"ts": ts, "hours": h})
            elif ev == "Login" and hs and ts >= login_ts.get(user, ""):
                login_ts[user] = ts; hours_alive[user] = int(hs.group(1))
            elif ev.startswith("Level Changed"):
                lm = re.search(r"\[([A-Za-z ]+)\]\[(\d+)\]", rest)
                if lm:
                    best[user][lm.group(1)] = max(best[user].get(lm.group(1), 0), int(lm.group(2)))
            elif "=" in ev and "," in ev:   # snapshot completo de skills: [Cooking=0, Fitness=8, ...]
                snap = {}
                for it in ev.split(","):
                    if "=" in it:
                        k, v = it.strip().split("=", 1)
                        try: snap[k] = int(v)
                        except ValueError: pass
                for k, v in snap.items():
                    best[user][k] = max(best[user].get(k, 0), v)
                if ts >= cur_ts.get(user, ""):
                    cur_ts[user] = ts; cur[user] = snap

    extra = ler_traits(dic)
    online = set(ler_online())

    players = {}
    for cid, kv in chars.items():
        u = kv.get("username", "")
        p = players.setdefault(u, {"user": u, "kills": 0, "distance": 0.0, "gametime": 0.0, "daily": 0, "broken": 0,
                                   "vehicle": 0, "alive": None, "name": None, "last": 0, "cur_kills": 0, "chars": [],
                                   "brokenList": collections.Counter(), "weapons": collections.Counter(), "cats": collections.Counter()})
        k = int(float(kv.get("lastSeenKills", 0) or 0))
        dead = kv.get("isDead") == "true"
        hours = float(kv.get("gameTimeSeconds", 0) or 0) / 3600
        if dead and k == 0 and hours < 0.1:
            continue   # respawn imediato (segundos de jogo): nao conta como personagem
        p["kills"] += k
        p["distance"] += float(kv.get("distance", 0) or 0); p["gametime"] += float(kv.get("gameTimeSeconds", 0) or 0)
        p["daily"] = max(p["daily"], int(float(kv.get("dailyRecord", 0) or 0)))
        p["broken"] += int(float(kv.get("brokenWeaponsTotal", 0) or 0)); p["vehicle"] += int(float(kv.get("vehicleKills", 0) or 0))
        p["brokenList"].update(plist(kv.get("brokenWeapons")))
        p["weapons"].update(plist(kv.get("weapons"))); p["cats"].update(plist(kv.get("categories")))
        ls = int(float(kv.get("lastSeenRealTimestamp", 0) or 0))
        nome = (kv.get("forename", "") + " " + kv.get("surname", "")).replace("Unknown", "").strip()
        p["chars"].append({"name": nome, "kills": k, "dead": dead, "last": ls,
                           "deathTs": int(float(kv.get("deathRealTimestamp", 0) or 0)) if dead else 0,
                           "km": round(float(kv.get("distance", 0) or 0) / 1000, 1), "hours": round(hours, 1),
                           "daily": int(float(kv.get("dailyRecord", 0) or 0)),
                           "broken": int(float(kv.get("brokenWeaponsTotal", 0) or 0)),
                           "vehicle": int(float(kv.get("vehicleKills", 0) or 0)),
                           "weapons": sorted(plist(kv.get("weapons")).items(), key=lambda x: -x[1]),
                           "series": series(kv.get("dailySeries"))})
        if ls >= p["last"]:
            p["last"] = ls; p["alive"] = not dead; p["cur_kills"] = k; p["name"] = nome

    def skills_sorted(d):
        return sorted(d.items(), key=lambda x: (-x[1], x[0]))

    out = []
    todos = set(players) | set(deaths) | set(cur)
    for u in todos:
        p = players.get(u)
        dl = deaths.get(u, [])
        ex = extra.get(u, {})
        base = {"user": u, "name": (p and p["name"]) or ex.get("charName", ""), "alive": p["alive"] if p else None,
                "online": u in online, "prof": ex.get("prof", ""), "traits": ex.get("traits", []), "favs": ex.get("favs", []),
                "deaths": len(dl), "deathsList": sorted(dl, key=lambda d: d["ts"], reverse=True),
                "bestHours": max([d["hours"] for d in dl] + [hours_alive.get(u, 0)]),
                "curHours": hours_alive.get(u, 0) if (p and p["alive"]) else 0,
                "skillsCur": cur.get(u, {}), "skillsBest": skills_sorted(best.get(u, {})),
                "firstSeen": first_seen.get(u, ""), "lastSeen": last_seen.get(u, "")}
        if p:
            p["chars"].sort(key=lambda c: -c["last"])
            base.update({"kills": p["kills"], "curKills": p["cur_kills"], "km": round(p["distance"] / 1000, 1),
                         "hoursPlayed": round(p["gametime"] / 3600, 1), "daily": p["daily"], "broken": p["broken"],
                         "vehicle": p["vehicle"], "chars": p["chars"],
                         "brokenList": sorted(p["brokenList"].items(), key=lambda x: -x[1]),
                         "weapons": sorted(p["weapons"].items(), key=lambda x: -x[1]),
                         "cats": sorted(p["cats"].items(), key=lambda x: -x[1])})
        else:
            base.update({"kills": 0, "curKills": 0, "km": 0, "hoursPlayed": 0, "daily": 0, "broken": 0, "vehicle": 0,
                         "chars": [], "brokenList": [], "weapons": [], "cats": []})
        out.append(base)
    out.sort(key=lambda r: (-r["curKills"], -r["kills"]))

    agora = datetime.datetime.now()
    sandbox, sandbox_meta = ler_sandbox()
    ini, mods_ids, ws = ler_ini()
    data = {"sandbox": sandbox, "sandboxMeta": sandbox_meta, "ini": ini, "modIds": mods_ids, "mods": ler_mods(ws),
            "generated": agora.strftime("%d/%m/%Y %H:%M"), "generatedIso": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "server": INFO_SERVIDOR, "online": sorted(online), "players": out,
            "dict": {"traits": dic["traits"], "profs": dic["profs"]}}

    js = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    open(os.path.join(AQUI, "data.json"), "w", encoding="utf-8").write(js)
    tpl = open(os.path.join(AQUI, "ranking.tpl.html"), encoding="utf-8").read()
    html = tpl.replace("__DATA__", js.replace("</", "<\\/"))
    saida = os.path.join(AQUI, "ranking.html")
    open(saida, "w", encoding="utf-8").write(html)
    print(f"ranking.html e data.json gerados: {len(out)} jogadores, {len(online)} online")
    return [saida, os.path.join(AQUI, "data.json")]


def enviar(arquivos):
    h = HOSPEDAGEM
    nomes = {"ranking.html": "index.html", "data.json": "data.json"}
    if h["tipo"] == "worker":
        if not h.get("url") or not h.get("token"):
            print("envio desligado (HOSPEDAGEM.url/token vazios)"); return
        import urllib.request
        dj = [a for a in arquivos if a.endswith("data.json")][0]
        req = urllib.request.Request(h["url"].rstrip("/") + "/data.json", data=open(dj, "rb").read(), method="PUT",
                                     headers={"Authorization": "Bearer " + h["token"], "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=60) as r:
            print("enviado data.json ->", h["url"], r.status)
        return
    if h["tipo"] == "supabase":
        if not h.get("url") or not h.get("key"):
            print("envio desligado (HOSPEDAGEM.url/key vazios)"); return
        import urllib.request
        for a in arquivos:
            nome = nomes[os.path.basename(a)]
            caminho = "/".join(x for x in [h["bucket"], h["pasta"].strip("/"), nome] if x)
            destino = f"{h['url'].rstrip('/')}/storage/v1/object/{caminho}"
            ct = "text/html; charset=utf-8" if nome.endswith(".html") else "application/json"
            req = urllib.request.Request(destino, data=open(a, "rb").read(), method="PUT",
                                         headers={"Authorization": "Bearer " + h["key"], "apikey": h["key"],
                                                  "Content-Type": ct, "x-upsert": "true", "Cache-Control": "max-age=30"})
            with urllib.request.urlopen(req, timeout=60) as r:
                print("enviado", nome, "->", r.status)
        return
    if not h.get("host"):
        print("envio para hospedagem desligado (HOSPEDAGEM.host vazio)")
        return
    if h["tipo"] == "sftp":
        import paramiko
        t = paramiko.Transport((h["host"], h["port"]))
        t.connect(username=h["user"], password=h["password"])
        s = paramiko.SFTPClient.from_transport(t)
        for a in arquivos:
            s.put(a, posixpath.join(h["pasta"], nomes[os.path.basename(a)]))
        s.close(); t.close()
    else:
        from ftplib import FTP
        ftp = FTP(); ftp.connect(h["host"], h["port"]); ftp.login(h["user"], h["password"])
        ftp.cwd(h["pasta"])
        for a in arquivos:
            with open(a, "rb") as fp:
                ftp.storbinary("STOR " + nomes[os.path.basename(a)], fp)
        ftp.quit()
    print(f"enviado para {h['host']}:{h['pasta']}")


if __name__ == "__main__":
    if "--sem-download" not in sys.argv:
        baixar()
    arquivos = montar()
    enviar(arquivos)
