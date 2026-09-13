import '../../data/models/view_models.dart';
import '../../data/repositories/report_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../utils/formatters.dart';

/// Renders the read-only pages served over the local network by
/// [SyncServer], so an admin can share a link with colleagues on the
/// same Wi-Fi instead of passing a laptop around.
///
/// These pages are deliberately plain server-rendered HTML with inline
/// CSS: they must open on any phone browser on the network with no
/// build step, no assets and no external requests. They read the same
/// repositories the app uses, so the numbers always match what is on
/// screen.
class WebReportPages {
  WebReportPages._();

  static final _reportRepo = ReportRepository();
  static final _transactionRepo = TransactionRepository();
  static final _settingsRepo = SettingsRepository();

  /// Escapes text coming from the database before it is interpolated
  /// into HTML — product designations are free text.
  static String esc(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  static String _statusClass(StockStatus status) {
    switch (status) {
      case StockStatus.enStock:
        return 'ok';
      case StockStatus.stockFaible:
        return 'low';
      case StockStatus.rupture:
        return 'out';
      case StockStatus.stockNegatif:
        return 'neg';
    }
  }

  // --- Stock report ----------------------------------------------------

  static Future<String> stockPage() async {
    final rows = await _reportRepo.getReportRows();
    final counts = await _reportRepo.getStatusCounts();
    final settings = await _settingsRepo.getSettings();

    final body = StringBuffer()
      ..writeln('<div class="kpis">')
      ..writeln(_kpi('Produits', '${counts.total}', 'accent'))
      ..writeln(_kpi('En stock', '${counts.enStock}', 'ok'))
      ..writeln(_kpi('Stock faible', '${counts.stockFaible}', 'low'))
      ..writeln(_kpi('Rupture', '${counts.rupture}', 'out'))
      ..writeln('</div>')
      ..writeln('<input id="q" class="search" type="search" '
          'placeholder="Rechercher une référence ou une désignation…" '
          'autocomplete="off">')
      ..writeln('<div class="count"><span id="shown">${rows.length}</span> '
          'ligne(s)</div>')
      ..writeln('<table id="tbl"><thead><tr>'
          '<th>RÉFÉRENCE</th><th>DÉSIGNATION</th><th>UNITÉ</th>'
          '<th>MAGASIN</th><th class="n">INITIAL</th><th class="n">ENTRÉES</th>'
          '<th class="n">SORTIES</th><th class="n">ACTUEL</th><th>STATUT</th>'
          '</tr></thead><tbody>');

    for (final row in rows) {
      final cls = _statusClass(row.status);
      body
        ..writeln('<tr>')
        ..writeln('<td data-l="Référence" class="ref">${esc(row.reference)}</td>')
        ..writeln('<td data-l="Désignation">${esc(row.designation)}</td>')
        ..writeln('<td data-l="Unité">${esc(row.unit)}</td>')
        ..writeln('<td data-l="Magasin">${esc(row.storeName)}</td>')
        ..writeln('<td data-l="Initial" class="n">${row.initialStock}</td>')
        ..writeln('<td data-l="Entrées" class="n ok">+ ${row.entries}</td>')
        ..writeln('<td data-l="Sorties" class="n out">− ${row.outputs}</td>')
        ..writeln('<td data-l="Actuel" class="n $cls b">${row.current}</td>')
        ..writeln('<td data-l="Statut">'
            '<span class="badge $cls">${esc(row.status.label)}</span></td>')
        ..writeln('</tr>');
    }
    body.writeln('</tbody></table>');

    return _shell(
      title: 'Stock',
      company: settings.name,
      active: 'stock',
      body: body.toString(),
    );
  }

  // --- Movements -------------------------------------------------------

  static Future<String> movementsPage() async {
    final rows = await _transactionRepo.getTransactions();
    final settings = await _settingsRepo.getSettings();

    final body = StringBuffer()
      ..writeln('<input id="q" class="search" type="search" '
          'placeholder="Rechercher…" autocomplete="off">')
      ..writeln('<div class="count"><span id="shown">${rows.length}</span> '
          'mouvement(s)</div>')
      ..writeln('<table id="tbl"><thead><tr>'
          '<th>DATE</th><th>TYPE</th><th>RÉFÉRENCE</th><th>DÉSIGNATION</th>'
          '<th>MAGASIN</th><th>PARTENAIRE</th><th class="n">ENTRÉE</th>'
          '<th class="n">SORTIE</th><th class="n">STOCK APRÈS</th>'
          '</tr></thead><tbody>');

    for (final row in rows) {
      final isEntry = row.type == TransactionType.entry;
      body
        ..writeln('<tr>')
        ..writeln('<td data-l="Date">${esc(formatDisplayDate(row.date))}</td>')
        ..writeln('<td data-l="Type" class="${isEntry ? 'ok' : 'out'} b">'
            '${isEntry ? 'Entrée' : 'Sortie'}</td>')
        ..writeln('<td data-l="Référence" class="ref">${esc(row.reference)}</td>')
        ..writeln('<td data-l="Désignation">${esc(row.designation)}</td>')
        ..writeln('<td data-l="Magasin">${esc(row.storeName)}</td>')
        ..writeln('<td data-l="Partenaire">'
            '${row.partner.isEmpty ? '—' : esc(row.partner)}</td>')
        ..writeln('<td data-l="Entrée" class="n ok">'
            '${row.inQty > 0 ? '+ ${row.inQty}' : '—'}</td>')
        ..writeln('<td data-l="Sortie" class="n out">'
            '${row.outQty > 0 ? '− ${row.outQty}' : '—'}</td>')
        ..writeln('<td data-l="Solde" class="n b">${row.balance}</td>')
        ..writeln('</tr>');
    }
    body.writeln('</tbody></table>');

    return _shell(
      title: 'Mouvements',
      company: settings.name,
      active: 'movements',
      body: body.toString(),
    );
  }

  static String notFoundPage() => _shell(
        title: 'Introuvable',
        company: 'SOCOGEN',
        active: '',
        body: '<p class="empty">Cette page n\'existe pas. '
            '<a href="/">Retour au stock</a>.</p>',
      );

  static String _kpi(String label, String value, String cls) =>
      '<div class="kpi"><span class="kpi-l">${esc(label)}</span>'
      '<span class="kpi-v $cls">${esc(value)}</span></div>';

  // --- Page shell ------------------------------------------------------

  static String _shell({
    required String title,
    required String company,
    required String active,
    required String body,
  }) {
    final stamp = DateTime.now();
    final time = '${stamp.day.toString().padLeft(2, '0')}/'
        '${stamp.month.toString().padLeft(2, '0')}/${stamp.year} à '
        '${stamp.hour.toString().padLeft(2, '0')}:'
        '${stamp.minute.toString().padLeft(2, '0')}';

    return '''<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(company)} — $title</title>
<style>
:root{--bg:#0d1117;--surface:#161b22;--elev:#111827;--border:#21262d;
--strong:#30363d;--fg:#e6edf3;--dim:#8b949e;--muted:#484f58;--accent:#58a6ff;
--ok:#3fb950;--low:#d29922;--out:#f85149;--neg:#db61db}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
font:14px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
header{background:#010409;border-bottom:1px solid var(--border);
padding:14px 20px;position:sticky;top:0;z-index:5}
.brand{display:flex;align-items:center;gap:10px}
.mark{width:30px;height:30px;border-radius:8px;flex:none;
background:linear-gradient(135deg,#58a6ff,#1f6feb);color:#fff;font-weight:800;
display:flex;align-items:center;justify-content:center}
h1{font-size:16px;margin:0;font-weight:700}
.sub{color:var(--dim);font-size:11px}
nav{display:flex;gap:8px;margin-top:12px;flex-wrap:wrap}
nav a{color:var(--dim);text-decoration:none;font-size:13px;font-weight:600;
padding:6px 12px;border-radius:999px;border:1px solid var(--border)}
nav a.on{color:var(--accent);background:#1c2d4a;border-color:transparent}
main{padding:16px 20px 40px;max-width:1400px;margin:0 auto}
.kpis{display:grid;gap:10px;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));
margin-bottom:16px}
.kpi{background:var(--elev);border:1px solid var(--border);border-radius:10px;
padding:12px 14px;display:flex;flex-direction:column;gap:4px}
.kpi-l{font-size:10px;letter-spacing:1.1px;color:var(--dim);font-weight:700;
text-transform:uppercase}
.kpi-v{font-size:22px;font-weight:800;font-variant-numeric:tabular-nums}
.search{width:100%;padding:11px 14px;border-radius:8px;background:var(--surface);
border:1px solid var(--border);color:var(--fg);font-size:14px}
.search:focus{outline:none;border-color:var(--accent)}
.count{color:var(--muted);font-size:11px;margin:10px 2px}
table{width:100%;border-collapse:collapse;background:var(--surface);
border:1px solid var(--border);border-radius:10px;overflow:hidden}
th{font-size:10px;letter-spacing:.8px;color:var(--dim);text-align:left;
background:var(--elev);padding:10px;text-transform:uppercase;white-space:nowrap}
td{padding:9px 10px;border-top:1px solid var(--border);vertical-align:top}
tr:nth-child(even) td{background:rgba(255,255,255,.015)}
.n{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.b{font-weight:700}
.ref{color:var(--accent);font-weight:700}
.ok{color:var(--ok)}.low{color:var(--low)}.out{color:var(--out)}
.neg{color:var(--neg)}
.badge{display:inline-block;padding:2px 8px;border-radius:6px;font-size:11px;
font-weight:700;border:1px solid}
.badge.ok{background:rgba(63,185,80,.15);border-color:rgba(63,185,80,.4)}
.badge.low{background:rgba(210,153,34,.15);border-color:rgba(210,153,34,.4)}
.badge.out{background:rgba(248,81,73,.15);border-color:rgba(248,81,73,.4)}
.badge.neg{background:rgba(219,97,219,.15);border-color:rgba(219,97,219,.4)}
.empty{color:var(--dim);text-align:center;padding:40px 0}
footer{color:var(--muted);font-size:11px;text-align:center;padding:20px}
a{color:var(--accent)}
/* Phones: each row becomes a labelled card, mirroring the app. */
@media(max-width:760px){
 thead{display:none}
 table,tbody,tr,td{display:block;width:100%}
 table{border:0;background:none}
 tr{background:var(--surface);border:1px solid var(--border);
 border-radius:10px;margin-bottom:10px;padding:6px 2px}
 tr:nth-child(even) td{background:none}
 td{border:0;display:flex;justify-content:space-between;gap:14px;
 padding:5px 12px}
 td::before{content:attr(data-l);color:var(--muted);font-size:11px;
 text-transform:uppercase;letter-spacing:.6px;flex:none}
 .n{text-align:right}
}
</style>
</head>
<body>
<header>
  <div class="brand">
    <div class="mark">S</div>
    <div>
      <h1>${esc(company)}</h1>
      <div class="sub">Consultation du stock — lecture seule</div>
    </div>
  </div>
  <nav>
    <a href="/" class="${active == 'stock' ? 'on' : ''}">Stock</a>
    <a href="/mouvements" class="${active == 'movements' ? 'on' : ''}">Mouvements</a>
  </nav>
</header>
<main>
$body
</main>
<footer>Données au $time · actualisez la page pour les dernières valeurs</footer>
<script>
(function(){
  var q=document.getElementById('q');
  if(!q)return;
  var rows=[].slice.call(document.querySelectorAll('#tbl tbody tr'));
  var shown=document.getElementById('shown');
  q.addEventListener('input',function(){
    var t=q.value.toLowerCase();
    var n=0;
    rows.forEach(function(r){
      var hit=r.textContent.toLowerCase().indexOf(t)>-1;
      r.style.display=hit?'':'none';
      if(hit)n++;
    });
    if(shown)shown.textContent=n;
  });
})();
</script>
</body>
</html>''';
  }
}
