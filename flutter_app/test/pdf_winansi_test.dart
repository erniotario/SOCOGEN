import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ce que les documents imprimés ont le droit d'écrire.
///
/// Les polices intégrées du paquet `pdf` n'encodent que WinAnsi, et un
/// caractère en dehors est **laissé tomber sans rien dire** : pas
/// d'exception, pas de test rouge, seulement une ligne
/// `Unable to find a font to draw` perdue dans la sortie d'un build.
/// Le papier sort avec un trou à la place, et c'est le client qui le
/// découvre.
///
/// Les coupables ne sont pas exotiques : le tiret cadratin `—`, les
/// points de suspension `…`, le signe moins `−`, la flèche `→` — tout
/// ce qu'on tape sans y penser en écrivant du français soigné. Les
/// accents, eux, passent : `é` sort en octet 233 et le `°` en 176.
///
/// Ce test lit le code des services PDF et refuse tout caractère
/// au-dessus de U+00FF hors commentaire. Il ne garde que les fichiers
/// qui impriment : les pages HTML servies en UTF-8 n'ont pas cette
/// contrainte.
void main() {
  test('aucun document imprimé ne contient de caractère hors WinAnsi', () {
    final fautes = <String>[];

    for (final fichier in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.replaceAll(r'\', '/').endsWith('_pdf_service.dart'))) {
      final lignes = fichier.readAsLinesSync();
      for (var i = 0; i < lignes.length; i++) {
        final ligne = lignes[i];
        // Les commentaires ont le droit d'écrire du français soigné :
        // ils ne sortent pas sur le papier. Seules les lignes entières
        // de commentaire sont retirées, ce qui suffit — le style du
        // projet ne met pas de commentaire en fin de ligne de code.
        if (ligne.trimLeft().startsWith('//')) continue;
        final coupables = ligne.runes.where((r) => r > 0xFF).toSet();
        if (coupables.isEmpty) continue;
        final noms = coupables
            .map((r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}')
            .join(', ');
        fautes.add('${fichier.path}:${i + 1} — $noms');
      }
    }

    expect(
      fautes,
      isEmpty,
      reason: 'Ces caractères seront effacés silencieusement du PDF. '
          'Remplacez-les par leur équivalent Latin-1 : "-" pour un '
          'tiret, "..." pour des points de suspension, "|" ou "->" '
          'pour une flèche.\n${fautes.join('\n')}',
    );
  });

  test('le test lui-même trouve bien les fichiers à surveiller', () {
    // Sans cela, un renommage de fichier rendrait le test vert en ne
    // regardant plus rien — le pire état possible pour un garde-fou.
    final fichiers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.replaceAll(r'\', '/').endsWith('_pdf_service.dart'))
        .toList();

    expect(fichiers.length, greaterThanOrEqualTo(3),
        reason: 'ticket, facture, clôture et transactions au minimum');
  });
}
