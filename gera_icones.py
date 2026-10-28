# -*- coding: utf-8 -*-
"""Extrai icones do jogo (traits, profissoes e armas, incluindo as dos mods do servidor) para a pasta icons/
e gera icones.json. Rode no PC com o jogo instalado:  py -3 gera_icones.py   (pip install pillow)"""
import os, re, io, json, glob, struct, shutil
from PIL import Image

GAME = r"C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid\media"
WORKSHOP = r"C:\Program Files (x86)\Steam\steamapps\workshop\content\108600"
AQUI = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(AQUI, "icons")
os.makedirs(OUT, exist_ok=True)


def ler_pack(path, index):
    b = open(path, "rb").read(); pos = 0
    def i32():
        nonlocal pos; v = struct.unpack_from("<i", b, pos)[0]; pos += 4; return v
    def s():
        nonlocal pos; n = i32(); v = b[pos:pos + n].decode("latin-1"); pos += n; return v
    def printable(bs): return all(32 <= c < 127 for c in bs)
    if b[:4] == b"PZPK":
        pos = 4; i32()                      # versao
    n = i32()
    for _ in range(n):
        s(); ns = i32()
        ln = struct.unpack_from("<i", b, pos)[0]
        if not (0 < ln < 200 and printable(b[pos + 4:pos + 4 + ln])):
            i32()                           # campo extra presente em alguns packs
        subs = [(s(), [i32() for _ in range(8)]) for _ in range(ns)]
        sig = b.find(b"\x89PNG", pos, pos + 64)
        if sig < 0: raise ValueError("png nao encontrado em " + path)
        iend = b.find(b"IEND", sig) + 8
        for nm, v in subs:
            index[nm] = (path, sig, iend - sig, v[0], v[1], v[2], v[3])
        pos = iend
        if b[pos:pos + 4] == b"\xef\xbe\xad\xde": pos += 4


index = {}
for pack in ["UI.pack", "UI2.pack"]:
    ler_pack(os.path.join(GAME, "texturepacks", pack), index)
print("sprites indexados:", len(index))
low = {k.lower(): k for k in index}

_pages = {}
def sprite(nm):
    path, off, ln, x, y, w, h = index[nm]
    key = (path, off)
    if key not in _pages:
        with open(path, "rb") as f:
            f.seek(off); _pages[key] = Image.open(io.BytesIO(f.read(ln))).convert("RGBA")
    return _pages[key].crop((x, y, x + w, y + h))

def salvar_sprite(nm, arquivo):
    sprite(nm).save(os.path.join(OUT, arquivo))

dic = json.load(open(os.path.join(AQUI, "dicionario.json"), encoding="utf-8"))
out = {"traits": {}, "profs": {}, "items": {}, "names": {}}

# traits: sprite trait_<id>; alguns so existem soltos em media/ui/Traits
for tid in dic["traits"]:
    nome = "trait_" + tid.split(":", 1)[1]
    if nome.lower() in low:
        salvar_sprite(low[nome.lower()], nome + ".png"); out["traits"][tid] = nome + ".png"
    elif os.path.exists(os.path.join(GAME, "ui", "Traits", nome + ".png")):
        Image.open(os.path.join(GAME, "ui", "Traits", nome + ".png")).convert("RGBA").save(os.path.join(OUT, nome + ".png"))
        out["traits"][tid] = nome + ".png"

# profissoes: profession_<id>2, profession_<id>, excecoes
PROF_ALIAS = {"mechanics": "profession_mechanic", "fisherman": "profession_fisher2", "carpenter": "profession_hammer2"}
for pid in dic["profs"]:
    base = pid.split(":", 1)[1]
    for cand in [PROF_ALIAS.get(base, ""), "profession_" + base + "2", "profession_" + base, "Prof_" + base]:
        if cand and cand.lower() in low:
            nm = low[cand.lower()]; salvar_sprite(nm, nm + ".png"); out["profs"][pid] = nm + ".png"; break

# armas: scripts do jogo e dos mods do servidor (mods_cache.json tem os ids da Workshop)
mods = list(json.load(open(os.path.join(AQUI, "mods_cache.json"), encoding="utf-8")).keys()) if os.path.exists(os.path.join(AQUI, "mods_cache.json")) else []
scripts = glob.glob(os.path.join(GAME, "scripts", "**", "*.txt"), recursive=True)
texturas_mod = {}
for mid in mods:
    raiz = os.path.join(WORKSHOP, mid)
    scripts += glob.glob(os.path.join(raiz, "**", "media", "scripts", "**", "*.txt"), recursive=True)
    for png in glob.glob(os.path.join(raiz, "**", "media", "textures", "**", "Item_*.png"), recursive=True):
        texturas_mod.setdefault(os.path.basename(png).lower(), png)

itens = {}
for f in scripts:
    txt = open(f, encoding="utf-8", errors="ignore").read()
    mod = re.search(r"\bmodule\s+(\w+)", txt); modulo = mod.group(1) if mod else "Base"
    for m in re.finditer(r"\bitem\s+(\w+)\s*\{(.*?)\n\s*\}", txt, re.S):
        body = m.group(2)
        if not re.search(r"\bItemType\s*=\s*base:weapon\b|\bType\s*=\s*Weapon\b", body): continue
        ic = re.search(r"\bIcon\s*=\s*([^,\n]+)", body); ift = re.search(r"\bIconsForTexture\s*=\s*([^,\n]+)", body)
        dn = re.search(r"\bDisplayName\s*=\s*([^,\n]+)", body)
        cands = []
        if ic: cands.append(ic.group(1).strip())
        if ift: cands.append(ift.group(1).split(";")[0].strip())
        cands.append(m.group(1))
        itens[modulo + "." + m.group(1)] = (cands, dn.group(1).strip() if dn else m.group(1))

en = json.load(open(os.path.join(GAME, "lua", "shared", "Translate", "EN", "ItemName.json"), encoding="utf-8"))
for tipo, (cands, dn) in itens.items():
    out["names"][tipo] = en.get(tipo, dn)
    for c in cands:
        nm = "Item_" + c
        if nm.lower() in low:
            real = low[nm.lower()]; salvar_sprite(real, real + ".png"); out["items"][tipo] = real + ".png"; break
        if (nm + ".png").lower() in texturas_mod:
            src = texturas_mod[(nm + ".png").lower()]; dst = nm + ".png"
            Image.open(src).convert("RGBA").save(os.path.join(OUT, dst)); out["items"][tipo] = dst; break

json.dump(out, open(os.path.join(AQUI, "icones.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
print(f"traits={len(out['traits'])}/{len(dic['traits'])} profissoes={len(out['profs'])}/{len(dic['profs'])} armas={len(out['items'])}/{len(itens)} -> {OUT}")
