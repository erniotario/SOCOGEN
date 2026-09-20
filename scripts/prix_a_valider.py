"""Propose un prix pour les articles qui en manquent, à valider à la main.

Usage :
    python scripts/prix_a_valider.py GESCOM.gcm socogen_stock.db sortie.xlsx

Pourquoi ce script existe. Le catalogue de l'application a été recodé
depuis l'export Sage : sur 723 articles, 87 se retrouvent par référence
et 54 de plus par désignation exacte. Restent 211 articles qui portent
du stock et n'ont pas de prix — ceux-là seuls empêchent de vendre.

Pour eux, l'appariement ne peut être qu'approché, et un appariement
approché appliqué sans relecture est exactement ce que ce dépôt refuse
partout ailleurs : « PARLE G 14G » et « PARLE G 18G » partagent 78 % de
leurs mots et ne sont pas le même produit. Un prix faux ne corrompt pas
le stock, mais il fabrique un chiffre d'affaires qui a l'air juste.

D'où une feuille de propositions plutôt qu'un import. Les lignes
douteuses — moins de 85 % de mots communs, ou un prix de vente sous le
prix d'achat — sont surlignées.


Ne décide rien. Chaque ligne montre côte à côte ce que dit
l'application et ce que dit Sage, pour qu'un humain tranche : « PARLE G
14G » et « PARLE G 18G » partagent 78 % de leurs mots et ne sont pas le
même produit.

Les quatre premières colonnes sont celles que l'import lit. Les
suivantes sont là pour la relecture et l'import les ignore : supprimez
les lignes fausses, enregistrez, importez.
"""
import re, struct, sys, sqlite3, zipfile, shutil, tempfile, os
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

REF_W, DES_W = 19, 69
DES_OFF = REF_W + 1
ENC = "mac_roman"
DES_RE = re.compile(rb"[\x03-\x45][\x20-\x7e\x80-\xff]{3,69}")
PA_OFF, PV_OFF = 152, 168
SEUIL = 0.70

def champ(buf, off, width):
    if off < 0 or off + 1 + width > len(buf): return None
    n = buf[off]
    if n == 0 or n > width: return None
    t = buf[off+1:off+1+n]
    if any(b < 32 or b == 127 for b in t): return None
    if any(b != 0 for b in buf[off+1+n:off+1+width]): return None
    return t.decode(ENC)

def prix(buf, off):
    if off + 8 > len(buf): return None
    (v,) = struct.unpack_from(">d", buf, off)
    if v != v or abs(v) == float("inf") or v <= 0: return None
    return round(v)

def jetons(s): return set(re.findall(r"[A-Z0-9]+", s.upper()))

gcm, base, sortie = sys.argv[1], sys.argv[2], sys.argv[3]
db = sqlite3.connect(base)
manquants = []
for ref, des, q in db.execute("""
  SELECT p.reference, p.designation,
    SUM(COALESCE(ps.initial_stock,0)
      + COALESCE((SELECT SUM(quantity) FROM stock_entries e
                  WHERE e.reference=p.reference AND e.store_id=ps.store_id),0)
      - COALESCE((SELECT SUM(quantity) FROM stock_outputs o
                  WHERE o.reference=p.reference AND o.store_id=ps.store_id),0))
  FROM products p JOIN product_stocks ps ON ps.product_id=p.id
  WHERE p.prix_vente IS NULL GROUP BY p.id"""):
    if (q or 0) > 0: manquants.append((ref.strip(), des.strip(), q))

with open(gcm, "rb") as f: data = f.read()
sage = {}
for m in DES_RE.finditer(data):
    d = m.start()
    if m.end() - d - 1 != data[d]: continue
    des = champ(data, d, DES_W)
    if des is None or len(des) < 3: continue
    r = d - DES_OFF
    ref = champ(data, r, REF_W)
    if ref is None or len(ref) < 2: continue
    pa, pv = prix(data, r + PA_OFF), prix(data, r + PV_OFF)
    if pa and pv: sage[(ref.strip(), des.strip())] = (pa, pv)

lignes, faibles = [], 0
for ref, des, q in manquants:
    ja = jetons(des)
    if not ja: continue
    best, score = None, 0.0
    for (sref, sdes), (pa, pv) in sage.items():
        js = jetons(sdes)
        if not js: continue
        s = len(ja & js) / len(ja | js)
        if s > score: best, score = (sref, sdes, pa, pv), s
    if score >= SEUIL: lignes.append((ref, des, q, *best, score))
    elif score >= 0.5: faibles += 1

lignes.sort(key=lambda l: -l[2])
wb = Workbook(); ws = wb.active; ws.title = "Produits"
ws.append(["Référence", "Désignation", "Prix d'achat", "Prix de vente",
           "— à relire —", "Stock", "Désignation Sage", "Réf. Sage",
           "Concordance"])
for c in ws[1]: c.font = Font(bold=True)
doute = PatternFill("solid", fgColor="FFF3CD")
for ref, des, q, sref, sdes, pa, pv, s in lignes:
    ws.append([ref, des, pa, pv, "", q, sdes, sref, round(s, 2)])
    if s < 0.85 or pv < pa:
        for c in ws[ws.max_row]: c.fill = doute
for col, w in {"A": 16, "B": 38, "C": 13, "D": 13, "E": 12,
               "F": 8, "G": 38, "H": 15, "I": 12}.items():
    ws.column_dimensions[col].width = w
ws.freeze_panes = "A2"
wb.save(sortie)

rels = "xl/_rels/workbook.xml.rels"
with zipfile.ZipFile(sortie) as src:
    items = [(i, src.read(i.filename)) for i in src.infolist()]
h, tmp = tempfile.mkstemp(suffix=".xlsx"); os.close(h)
with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as out:
    for i, payload in items:
        if i.filename == rels:
            payload = payload.replace(b'Target="/xl/', b'Target="')
        out.writestr(i, payload)
shutil.move(tmp, sortie)

surs = sum(1 for l in lignes if l[7] >= 0.85 and l[6] >= l[5])
print(f"{len(manquants)} articles sans prix mais avec du stock")
print(f"{len(lignes)} propositions (>= {SEUIL:.0%} de mots communs)")
print(f"   dont {surs} sans réserve, {len(lignes)-surs} surlignées à vérifier")
print(f"{faibles} correspondances trop faibles, écartées")
print(f"-> {sortie}")
