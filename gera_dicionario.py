# -*- coding: utf-8 -*-
"""Gera dicionario.json (traits, profissoes e skills em PT-BR) a partir dos arquivos do jogo.
Rode uma vez (ou quando o jogo atualizar):  py -3 gera_dicionario.py"""
import os, re, json

GAME = r"C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid\media"
AQUI = os.path.dirname(os.path.abspath(__file__))

ui = json.load(open(os.path.join(GAME, "lua", "shared", "Translate", "PTBR", "UI.json"), encoding="utf-8"))
ui_l = {k.lower(): v for k, v in ui.items()}

def blocks(path, kind):
    txt = open(path, encoding="utf-8", errors="ignore").read()
    out = {}
    for m in re.finditer(kind + r"_definition\s+(\S+)\s*\{(.*?)\}", txt, re.S):
        ident, body = m.group(1), m.group(2)
        kv = dict(re.findall(r"(\w+)\s*=\s*([^,\n]+)", body))
        out[ident] = kv
    return out

traits = {}
for ident, kv in blocks(os.path.join(GAME, "scripts", "generated", "characters", "character_traits.txt"), "character_trait").items():
    name = ui_l.get(kv.get("UIName", "").strip().lower(), ident.split(":")[-1])
    traits[ident] = {"n": name, "c": int(kv.get("Cost", "0").strip() or 0), "p": kv.get("IsProfessionTrait", "false").strip() == "true"}

profs = {}
for ident, kv in blocks(os.path.join(GAME, "scripts", "generated", "characters", "character_professions.txt"), "character_profession").items():
    profs[ident] = ui_l.get(kv.get("UIName", "").strip().lower(), ident.split(":")[-1])

perks = {}
for k, v in ui.items():
    m = re.match(r"UI_perks_(\w+)$", k)
    if m: perks[m.group(1)] = v

json.dump({"traits": traits, "profs": profs, "perks": perks}, open(os.path.join(AQUI, "dicionario.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
print(f"traits={len(traits)} profissoes={len(profs)} perks={len(perks)}")
