import os, re, json, glob, datetime, collections, posixpath, sys, sqlite3

AQUI = os.path.dirname(os.path.abspath(__file__))
DADOS = os.path.join(AQUI, "dados")
os.makedirs(DADOS, exist_ok=True)

_cfg = os.environ.get("PZ_CONFIG")
if not _cfg and os.path.exists(os.path.join(AQUI, "segredos.json")):
    _cfg = open(os.path.join(AQUI, "segredos.json"), encoding="utf-8").read()
CFG = json.loads(_cfg or "{}")
SRV = CFG.get("server", "")
R_STATS = ".cache/Lua/ttf_stats_mp"
R_BAGRES = ".cache/Lua/bagres_stats"
R_LOGS = ".cache/Logs"
R_PLAYERS = f".cache/Saves/Multiplayer/{SRV}/players.db"
R_USERS = f".cache/db/{SRV}.db"
R_SANDBOX = f".cache/Server/{SRV}_SandboxVars.lua"
R_INI = f".cache/Server/{SRV}.ini"
IGNORAR = [tuple(x) for x in CFG.get("ignorar", [])]
INI_PUBLICO = ["PVP", "PauseEmpty", "GlobalChat", "Open", "SafetySystem", "Map", "Public", "PublicName", "MaxPlayers",
               "SafehousePreventsLootRespawn", "DropOffWhiteListAfterDeath", "NoFire", "AnnounceDeath", "SaveWorldEveryMinutes",
               "PlayerSafehouse", "AdminSafehouse", "SafehouseAllowTrepass", "SafehouseAllowFire", "SafehouseAllowLoot",
               "SafehouseAllowRespawn", "SafehouseDaySurvivedToClaim", "AllowDestructionBySledgehammer", "SleepAllowed", "SleepNeeded",
               "KnockedDownAllowed", "SneakModeHideFromOtherPlayers", "SpeedLimit", "PlayerRespawnWithSelf", "PlayerRespawnWithOther",
               "FastForwardMultiplier", "Faction", "FactionDaySurvivedToCreate", "VoiceEnable", "Voice3D", "PerkLogs", "SteamVAC",
               "PlayerBumpPlayer", "HidePlayersBehindYou", "MapRemotePlayerVisibility", "DisableVehicleTowing", "DisableTrailerTowing",
               "BackupsCount", "ServerWelcomeMessage", "AllowCoop", "PVPMeleeDamageModifier", "PVPFirearmDamageModifier"]
TIPOS = ("_PerkLog.txt", "_admin.txt", "_user.txt", "_cmd.txt", "_chat.txt", "_ClientActionLog.txt")
ROLES_PT = {"admin": "Admin", "moderator": "Moderador", "gm": "Game Master", "observer": "Observador", "priority": "Prioridade", "user": "Jogador", "banned": "Banido"}


def baixar():
    import paramiko, socket
    sock = socket.create_connection((CFG["host"], int(CFG.get("port", 22))), timeout=30)
    sock.settimeout(120)
    t = paramiko.Transport(sock)
    t.connect(username=CFG["user"], password=CFG["password"])
    s = paramiko.SFTPClient.from_transport(t)
    s.get_channel().settimeout(120)
    for f in glob.glob(os.path.join(DADOS, "stats__*.txt")):
        os.remove(f)
    for f in s.listdir(R_STATS):
        if f.endswith(".txt"):
            s.get(posixpath.join(R_STATS, f), os.path.join(DADOS, "stats__" + f))
    for f in glob.glob(os.path.join(DADOS, "bagres__*.txt")):
        os.remove(f)
    try:
        for f in s.listdir(R_BAGRES):
            if f.endswith(".txt"):
                s.get(posixpath.join(R_BAGRES, f), os.path.join(DADOS, "bagres__" + f))
    except IOError:
        pass

    def walk(d):
        for e in s.listdir_attr(d):
            p = posixpath.join(d, e.filename)
            if e.longname.startswith("d"):
                yield from walk(p)
            elif e.filename.endswith(TIPOS):
                yield p
    for p in walk(R_LOGS):
        kind = next(k for k in TIPOS if p.endswith(k)).strip("_").replace(".txt", "").lower() + "__"
        s.get(p, os.path.join(DADOS, kind + p.replace(R_LOGS + "/", "").replace("/", "__")))
    for remoto, local in [(R_PLAYERS, "players.db"), (R_USERS, "users.db"), (R_SANDBOX, "sandbox.lua"), (R_INI, "server.ini")]:
        try:
            s.get(remoto, os.path.join(DADOS, local))
        except IOError:
            pass
    s.close(); t.close()


def plist(v):
    d = {}
    for it in (v or "").split("|"):
        if ":" in it:
            k, n = it.rsplit(":", 1)
            try:
                d[k] = d.get(k, 0) + int(float(n))
            except ValueError:
                pass
    return d


def series(v):
    out = []
    for it in (v or "").split("|"):
        f = it.split(",")
        if len(f) >= 2:
            try:
                out.append([int(float(f[0])), int(float(f[1]))])
            except ValueError:
                pass
    return out


LAB = set(open(os.path.join(AQUI, "receitas_lab.txt"), encoding="utf-8").read().split()) if os.path.exists(os.path.join(AQUI, "receitas_lab.txt")) else set()
LAB_CURA = {"ChmSynthesizeCure", "ChmDuplicateCure"}
LAB_VAC = {"ChmSynthesizePlainVaccine", "ChmSynthesizeQualityVaccine", "ChmSynthesizeAdvancedVaccine", "ChmDuplicateAdvancedVaccine"}


def lab_info(blob):
    toks = set(m.decode("latin-1") for m in re.findall(rb"[A-Za-z0-9_.]{4,60}", blob))
    sabe = toks & LAB
    return {"n": len(sabe), "cure": bool(sabe & LAB_CURA), "vaccine": bool(sabe & LAB_VAC),
            "has": any(t.endswith(("CmpSyringeWithCure", "CmpSyringeReusableWithCure")) for t in toks)}


def ler_traits(dic):
    out = {}
    p = os.path.join(DADOS, "players.db")
    if not os.path.exists(p):
        return out
    try:
        c = sqlite3.connect(p)
        for user, name, dead, blob in c.execute("select username, name, isDead, data from networkPlayers"):
            toks = list(dict.fromkeys(t.decode() for t in re.findall(rb"base:[A-Za-z0-9_]+", blob or b"")))
            favs = list(dict.fromkeys(f.decode("utf-8", "ignore")[4:] for f in re.findall(rb"Fav:[^\x00-\x1f]{2,40}", blob or b"")))
            out[user] = {"prof": next((t for t in toks if t in dic["profs"]), ""), "traits": [t for t in toks if t in dic["traits"]],
                         "favs": favs, "charName": (name or "").strip(),
                         "plants": sum(1 for t in toks if t.split(":", 1)[1] in PLANTAS),
                         "lab": lab_info(blob or b"")}
        c.close()
    except Exception:
        pass
    return out


def ler_adm():
    admins = []
    p = os.path.join(DADOS, "users.db")
    if os.path.exists(p):
        try:
            c = sqlite3.connect(p)
            roles = {rid: nome for rid, nome in c.execute("select id, name from role")}
            for user, role, last in c.execute("select username, role, lastConnection from whitelist"):
                rn = roles.get(role, "")
                if rn in ("admin", "moderator", "gm", "observer") and user != "admin":
                    admins.append({"user": user, "role": rn, "roleName": ROLES_PT.get(rn, rn), "last": last or ""})
            c.close()
        except Exception:
            pass
    acoes = []; vistos = set()
    rx_ts = re.compile(r"^\[(\d\d)-(\d\d)-(\d\d) (\d\d:\d\d:\d\d)[^\]]*\]\s*(?:\[IMPORTANT\]\s*)?(.*)$")
    regras = [
        (r"^(.+?) teleported to (-?\d+),(-?\d+),(-?\d+)\.?$", "teleporte", lambda m: f"teleportou para {m.group(2)},{m.group(3)}", lambda m: ""),
        (r"^(.+?) granted (\w+) access level on (.+?)\.?$", "acesso", lambda m: f"deu nível {ROLES_PT.get(m.group(2), m.group(2))} a {m.group(3)}", lambda m: m.group(3)),
        (r"^(.+?) created a horde of (\d+) zombies near (-?\d+),(-?\d+)\.?$", "horda", lambda m: f"criou uma horda de {m.group(2)} zumbis em {m.group(3)},{m.group(4)}", lambda m: ""),
        (r"^(.+?) removed zombies near (-?\d+),(-?\d+)\.?$", "limpeza", lambda m: f"removeu zumbis perto de {m.group(2)},{m.group(3)}", lambda m: ""),
        (r"^(.+?) added item (\S+) in (.+?)'s inventory\.?$", "item", lambda m: f"criou o item {m.group(2).replace('Base.', '')} para {m.group(3)}", lambda m: m.group(3)),
        (r"^(.+?) added ([\d.]+) (\w+) xp's to (.+?)\.?$", "xp", lambda m: f"deu {m.group(2)} de XP em {m.group(3)} para {m.group(4)}", lambda m: m.group(4)),
        (r"^(.+?) (banned|unbanned|kicked) (.+?)\.?$", "ban", lambda m: f"{ {'banned': 'baniu', 'unbanned': 'desbaniu', 'kicked': 'expulsou'}[m.group(2)] } {m.group(3)}", lambda m: m.group(3)),
        (r"^(.+?) (opened|closed) server\.?$", "servidor", lambda m: "abriu o servidor" if m.group(2) == "opened" else "fechou o servidor", lambda m: ""),
        (r"^(.+?) (.*)$", "outro", lambda m: m.group(2), lambda m: ""),
    ]
    for f in sorted(glob.glob(os.path.join(DADOS, "admin__*.txt"))):
        for line in open(f, encoding="utf-8", errors="ignore"):
            m = rx_ts.match(line.strip())
            if not m:
                continue
            dd, mm, yy, t, resto = m.groups()
            ts = f"20{yy}-{mm}-{dd} {t}"
            for pat, tipo, texto, alvo in regras:
                m2 = re.match(pat, resto)
                if m2:
                    autor = m2.group(1).strip()
                    if autor != "admin" and (ts, resto) not in vistos:
                        vistos.add((ts, resto))
                        acoes.append({"ts": ts, "actor": autor, "type": tipo, "text": texto(m2), "target": alvo(m2)})
                    break
    acoes.sort(key=lambda a: a["ts"], reverse=True)
    return {"admins": admins, "actions": acoes}


def ler_bagres():
    out = {}
    for f in glob.glob(os.path.join(DADOS, "bagres__*.txt")):
        kv = {}; user = None
        for line in open(f, encoding="utf-8", errors="ignore"):
            line = line.strip()
            if "=" not in line:
                continue
            k, v = line.split("=", 1)
            if k == "_user":
                user = v
            else:
                try:
                    kv[k] = float(v) if "." in v else int(v)
                except ValueError:
                    pass
        if user:
            out[user] = kv
    return out


def ler_online():
    online = set()
    rxn = re.compile(r"(\d{4}-\d\d-\d\d_\d\d-\d\d)_user")
    arqs = [f for f in glob.glob(os.path.join(DADOS, "user__*.txt")) if rxn.search(f)]
    atual = max(arqs, key=lambda f: rxn.search(f).group(1)) if arqs else None
    for f in ([atual] if atual else []):
        for line in open(f, encoding="utf-8", errors="ignore"):
            m = re.search(r'"([^"]+)" fully connected', line)
            if m:
                online.add(m.group(1)); continue
            m = re.search(r'"([^"]+)" disconnected player', line)
            if m:
                online.discard(m.group(1))
    return sorted(online)


def ler_atividade():
    acts = collections.defaultdict(collections.Counter); chat = collections.Counter()
    drives = collections.Counter(); veics = collections.defaultdict(set)
    rx = re.compile(r'^\[(\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)[^\]]*\] \d+ "([^"]+)" (\S+)')
    CATS = [("horsemod.", "horse"), ("RadArchery.bowStrainHold", "arrows"), ("that_damn_lib.silentPartInstall", "parts"), ("vehicle.installPart", "parts"),
            ("animal.", "animals"), ("map.setKnownInSquares", "maps"), ("SkillRecoveryJournal.", "journal"), ("object.emptyTrash", "trash")]
    for f in glob.glob(os.path.join(DADOS, "cmd__*.txt")):
        for line in open(f, encoding="utf-8", errors="ignore"):
            m = rx.match(line)
            if not m:
                continue
            cmd = m.group(8)
            for pref, cat in CATS:
                if cmd.startswith(pref):
                    acts[m.group(7)][cat] += 1
                    break
    for f in glob.glob(os.path.join(DADOS, "chat__*.txt")):
        for line in open(f, encoding="utf-8", errors="ignore"):
            m = re.search(r"Got message:ChatMessage\{chat=\w+, author='([^']+)'", line)
            if m:
                chat[m.group(1)] += 1
    for f in glob.glob(os.path.join(DADOS, "clientactionlog__*.txt")):
        for line in open(f, encoding="utf-8", errors="ignore"):
            m = re.search(r"\[ISEnterVehicle\]\[([^\]]+)\]\[[^\]]*\]\[([^\]]*)\]", line)
            if m:
                drives[m.group(1)] += 1; veics[m.group(1)].add(m.group(2))
    sess = collections.defaultdict(list); aberta = {}
    rxu = re.compile(r'^\[(\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)[^\]]*\] (?:\d+ )?"([^"]+)" (fully connected|disconnected player)')
    for f in sorted(glob.glob(os.path.join(DADOS, "user__*.txt"))):
        for line in open(f, encoding="utf-8", errors="ignore"):
            m = rxu.match(line)
            if not m:
                continue
            dd, mm, yy, H, M, S, u, ev = m.groups()
            ts = datetime.datetime(2000 + int(yy), int(mm), int(dd), int(H), int(M), int(S)) - datetime.timedelta(hours=3)
            if ev == "fully connected":
                aberta[u] = ts
            elif u in aberta:
                sess[u].append((aberta.pop(u), ts))
    agora = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) - datetime.timedelta(hours=3)
    for u, ts in aberta.items():
        sess[u].append((ts, agora))
    pres = {}
    for u, lst in sess.items():
        dias = sorted({a.date() for a, b in lst})
        streak = best = 0; prev = None
        for d in dias:
            streak = streak + 1 if prev and (d - prev).days == 1 else 1
            best = max(best, streak); prev = d
        noite = 0.0
        for a, b in lst:
            d = a.replace(hour=0, minute=0, second=0)
            while d < b:
                lo, hi = max(a, d), min(b, d + datetime.timedelta(hours=6))
                if hi > lo:
                    noite += (hi - lo).total_seconds() / 3600
                d += datetime.timedelta(days=1)
        pres[u] = {"days": len(dias), "streak": best, "night": round(noite, 1)}
    return acts, chat, drives, veics, pres


PLANTAS = {"basil", "chives", "cilantro", "lemongrass", "mint", "oregano", "parsley", "sage", "rosemary", "thyme", "hops", "black", "broadleaf", "comfrey",
           "common", "wild", "sweet", "carrot", "broccoli", "radish", "strawberry", "tomato", "potato", "cabbage", "corn", "kale", "green", "onion", "garlic",
           "soybean", "sugar", "bell", "cauliflower", "cucumber", "habanero", "jalapeno", "leek", "lettuce", "pumpkin", "spinach", "sunflower", "turnip",
           "watermelon", "zucchini", "chamomile", "marigold", "rose", "poppy", "lavender", "out", "ginseng", "dandelion", "plantain", "burdock", "nettle",
           "violet", "mushroom", "berry", "blueberry", "blackberry", "raspberry", "grape", "flax", "hemp", "tobacco", "barley", "wheat", "rye", "rice", "peanut"}


def ler_sandbox():
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
            if m:
                opts[int(m.group(1))] = m.group(2).strip()
            elif desc is None:
                desc = c
            continue
        m = re.match(r"^(\w+)\s*=\s*\{", line)
        if m:
            stack.append(m.group(1)); desc = None; opts = {}; continue
        if line.startswith("}"):
            if stack:
                stack.pop()
            continue
        m = re.match(r"^(\w+)\s*=\s*(.+?),?$", line)
        if m:
            k, v = m.group(1), m.group(2).strip()
            key = ".".join(stack[1:] + [k]) if len(stack) > 1 else k
            if v in ("true", "false"):
                val = (v == "true")
            elif v.startswith('"'):
                val = v.strip('"')
            else:
                try:
                    val = float(v) if "." in v else int(v)
                except ValueError:
                    val = v
            vals[key] = val
            if desc or opts:
                meta[key] = {"desc": desc or "", "opts": {str(a): b for a, b in opts.items()}}
            desc = None; opts = {}
    return vals, meta


def ler_ini():
    p = os.path.join(DADOS, "server.ini")
    out, ws = {}, []
    if not os.path.exists(p):
        return out, ws
    for raw in open(p, encoding="utf-8", errors="ignore"):
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        if k == "WorkshopItems":
            ws = [x for x in v.split(";") if x]
        elif k in INI_PUBLICO:
            out[k] = (v == "true") if v in ("true", "false") else v
    return out, ws


def ler_mods(ws):
    cpath = os.path.join(AQUI, "mods_cache.json")
    cache = json.load(open(cpath, encoding="utf-8")) if os.path.exists(cpath) else {}
    falta = [i for i in ws if i not in cache]
    if falta:
        try:
            import urllib.request, urllib.parse
            d = {"itemcount": len(falta)}
            for i, x in enumerate(falta):
                d[f"publishedfileids[{i}]"] = x
            req = urllib.request.Request("https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/",
                                         data=urllib.parse.urlencode(d).encode(), headers={"User-Agent": "Mozilla/5.0"})
            j = json.loads(urllib.request.urlopen(req, timeout=30).read())
            for it in j["response"]["publishedfiledetails"]:
                cache[it["publishedfileid"]] = {"title": it.get("title", "?"), "updated": it.get("time_updated", 0)}
            json.dump(cache, open(cpath, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
        except Exception:
            pass
    return [{"id": i, "title": cache.get(i, {}).get("title", i), "updated": cache.get(i, {}).get("updated", 0)} for i in ws]


def montar():
    def carrega(nome, padrao):
        p = os.path.join(AQUI, nome)
        return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else padrao
    dic = carrega("dicionario.json", {"traits": {}, "profs": {}})
    icones = carrega("icones.json", {})
    wcat = carrega("armas_categoria.json", {})

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
    first_lvl = collections.defaultdict(dict); morreu = {}; fenix = {}
    last_seen = {}; first_seen = {}

    def marca(user, perk, lvl, ts):
        d = first_lvl[user]
        for l in range(1, lvl + 1):
            if (perk, l) not in d or ts < d[(perk, l)]:
                d[(perk, l)] = ts
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
                if h > 0 and not any(a <= ts <= b for a, b in IGNORAR):
                    deaths[user].append({"ts": ts, "hours": h}); morreu[user] = True
            elif ev == "Login" and hs:
                if ts >= login_ts.get(user, ""):
                    login_ts[user] = ts; hours_alive[user] = int(hs.group(1))
                if morreu.get(user):
                    fenix[user] = max(fenix.get(user, 0), int(hs.group(1)))
            elif ev.startswith("Level Changed"):
                lm = re.search(r"\[([A-Za-z ]+)\]\[(\d+)\]", rest)
                if lm:
                    best[user][lm.group(1)] = max(best[user].get(lm.group(1), 0), int(lm.group(2)))
                    marca(user, lm.group(1), int(lm.group(2)), ts)
            elif "=" in ev and "," in ev:
                snap = {}
                for it in ev.split(","):
                    if "=" in it:
                        k, v = it.strip().split("=", 1)
                        try:
                            snap[k] = int(v)
                        except ValueError:
                            pass
                for k, v in snap.items():
                    best[user][k] = max(best[user].get(k, 0), v)
                    marca(user, k, v, ts)
                if ts >= cur_ts.get(user, ""):
                    cur_ts[user] = ts; cur[user] = snap

    extra = ler_traits(dic)
    online = set(ler_online())
    acts, chat, drives, veics, pres = ler_atividade()
    bagres = ler_bagres()
    first10 = collections.defaultdict(list)
    melhor = {}
    for u, d in first_lvl.items():
        for (perk, lvl), ts in d.items():
            if lvl == 10 and (perk not in melhor or ts < melhor[perk][0]):
                melhor[perk] = (ts, u)
    for perk, (ts, u) in melhor.items():
        first10[u].append(perk)

    def streaks(ser):
        kills = {d: k for d, k in ser}
        best = run = 0; prev = None
        for d in sorted(kills):
            run = run + 1 if (kills[d] > 0 and prev is not None and d == prev + 1) else (1 if kills[d] > 0 else 0)
            best = max(best, run); prev = d
        semana = 0
        for d in kills:
            semana = max(semana, sum(k for dd, k in kills.items() if d <= dd < d + 7))
        return best, semana

    players = {}
    for cid, kv in chars.items():
        u = kv.get("username", "")
        p = players.setdefault(u, {"kills": 0, "distance": 0.0, "gametime": 0.0, "daily": 0, "broken": 0, "alive": None,
                                   "name": None, "last": 0, "cur_kills": 0, "chars": [], "brokenList": collections.Counter()})
        k = int(float(kv.get("lastSeenKills", 0) or 0))
        dead = kv.get("isDead") == "true"
        hours = float(kv.get("gameTimeSeconds", 0) or 0) / 3600
        if dead and k == 0 and hours < 0.1:
            continue
        p["kills"] += k
        p["distance"] += float(kv.get("distance", 0) or 0); p["gametime"] += float(kv.get("gameTimeSeconds", 0) or 0)
        p["daily"] = max(p["daily"], int(float(kv.get("dailyRecord", 0) or 0)))
        p["broken"] += int(float(kv.get("brokenWeaponsTotal", 0) or 0))
        p["brokenList"].update(plist(kv.get("brokenWeapons")))
        ls = int(float(kv.get("lastSeenRealTimestamp", 0) or 0))
        nome = (kv.get("forename", "") + " " + kv.get("surname", "")).replace("Unknown", "").strip()
        p["chars"].append({"name": nome, "kills": k, "dead": dead, "last": ls,
                           "deathTs": int(float(kv.get("deathRealTimestamp", 0) or 0)) if dead else 0,
                           "km": round(float(kv.get("distance", 0) or 0) / 1000, 1), "hours": round(hours, 1),
                           "daily": int(float(kv.get("dailyRecord", 0) or 0)),
                           "broken": int(float(kv.get("brokenWeaponsTotal", 0) or 0)),
                           "series": series(kv.get("dailySeries"))})
        st, sem = streaks(series(kv.get("dailySeries")))
        p["killStreak"] = max(p.get("killStreak", 0), st); p["weekKills"] = max(p.get("weekKills", 0), sem)
        if ls >= p["last"]:
            p["last"] = ls; p["alive"] = not dead; p["cur_kills"] = k; p["name"] = nome

    out = []
    for u in set(players) | set(deaths) | set(cur):
        p = players.get(u)
        dl = deaths.get(u, [])
        ex = extra.get(u, {})
        base = {"user": u, "name": (p and p["name"]) or ex.get("charName", ""), "alive": p["alive"] if p else None,
                "online": u in online, "prof": ex.get("prof", ""), "traits": ex.get("traits", []), "favs": ex.get("favs", []),
                "deaths": len(dl), "deathsList": sorted(dl, key=lambda d: d["ts"], reverse=True),
                "bestHours": max([d["hours"] for d in dl] + [hours_alive.get(u, 0)]),
                "curHours": hours_alive.get(u, 0) if (p and p["alive"]) else 0,
                "skillsCur": cur.get(u, {}), "skillsBest": sorted(best.get(u, {}).items(), key=lambda x: (-x[1], x[0])),
                "skillsCurTs": {k: first_lvl[u].get((k, v), cur_ts.get(u, "")) for k, v in cur.get(u, {}).items() if v > 0},
                "firstSeen": first_seen.get(u, ""), "lastSeen": last_seen.get(u, ""),
                "acts": dict(acts.get(u, {})), "chat": chat.get(u, 0), "drives": drives.get(u, 0), "vehicles": len(veics.get(u, ())),
                "pres": pres.get(u, {"days": 0, "streak": 0, "night": 0}), "plants": ex.get("plants", 0),
                "lab": ex.get("lab", {"n": 0, "cure": False, "vaccine": False, "has": False}), "labN": ex.get("lab", {}).get("n", 0),
                "mod": bagres.get(u, {}),
                "phoenix": fenix.get(u, 0), "first10": first10.get(u, []),
                "killStreak": (p or {}).get("killStreak", 0), "weekKills": (p or {}).get("weekKills", 0)}
        if p:
            p["chars"].sort(key=lambda c: -c["last"])
            base.update({"kills": p["kills"], "curKills": p["cur_kills"], "km": round(p["distance"] / 1000, 1),
                         "hoursPlayed": round(p["gametime"] / 3600, 1), "daily": p["daily"], "broken": p["broken"],
                         "chars": p["chars"], "brokenList": sorted(p["brokenList"].items(), key=lambda x: -x[1])})
        else:
            base.update({"kills": 0, "curKills": 0, "km": 0, "hoursPlayed": 0, "daily": 0, "broken": 0, "chars": [], "brokenList": []})
        out.append(base)
    out.sort(key=lambda r: (-r["curKills"], -r["kills"]))

    try:
        from zoneinfo import ZoneInfo
        tz = ZoneInfo("America/Sao_Paulo")
    except Exception:
        tz = datetime.timezone(datetime.timedelta(hours=-3))
    sandbox, sandbox_meta = ler_sandbox()
    ini, ws = ler_ini()
    data = {"sandbox": sandbox, "sandboxMeta": sandbox_meta, "ini": ini, "mods": ler_mods(ws), "adm": ler_adm(),
            "generated": datetime.datetime.now(tz).strftime("%d/%m/%Y %H:%M"),
            "generatedIso": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "server": {"nome": CFG.get("nome", ""), "versao": CFG.get("versao", ""), "pop": CFG.get("pop", "")},
            "online": sorted(online), "players": out,
            "dict": {"traits": dic["traits"], "profs": dic["profs"], "icons": icones, "wcat": wcat}}
    usados = set()
    for pl in out:
        for k in pl.get("mod", {}):
            if k.startswith("craft."):
                usados.add(k[6:])
    nomes = {k: dic.get(k, {}) for k in ("animals", "farming", "fish")}
    nomes["recipes"] = {k: v for k, v in dic.get("recipes", {}).items() if k in usados}
    tipos = set(); en = {v: k for k, v in icones.get("names", {}).items()}
    for pl in out:
        for w, n in pl.get("brokenList", []): tipos.add(w)
        for f in pl.get("favs", []):
            if f in en: tipos.add(en[f])
        for k in pl.get("mod", {}):
            if k.startswith("kills.weapon."): tipos.add(k[13:])
    nomes["items"] = {k: v for k, v in dic.get("items", {}).items() if k in tipos}
    data["dict"]["nomes"] = nomes
    js = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    open(os.path.join(AQUI, "data.json"), "w", encoding="utf-8").write(js)
    tpl = os.path.join(AQUI, "ranking.tpl.html")
    if os.path.exists(tpl):
        html = open(tpl, encoding="utf-8").read().replace("__DATA__", js.replace("</", "<\\/"))
        open(os.path.join(AQUI, "ranking.html"), "w", encoding="utf-8").write(html)
    print(f"{len(out)} jogadores, {len(online)} online")
    return js


def enviar(js):
    if not CFG.get("url") or not CFG.get("token"):
        return
    import urllib.request
    req = urllib.request.Request(CFG["url"].rstrip("/") + "/data.json", data=js.encode("utf-8"), method="PUT",
                                 headers={"Authorization": "Bearer " + CFG["token"], "Content-Type": "application/json",
                                          "User-Agent": "ranking-updater/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        print("enviado", r.status)


if __name__ == "__main__":
    if "--sem-download" not in sys.argv:
        import time
        for tentativa in range(3):
            try:
                baixar(); break
            except Exception as e:
                print("download falhou:", e)
                if tentativa == 2:
                    raise
                time.sleep(40)
    enviar(montar())
