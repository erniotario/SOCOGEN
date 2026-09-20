/// Un déplacement de marchandises entre deux magasins de l'entreprise.
///
/// Avant cette fiche, déplacer des marchandises se faisait par une
/// sortie ici et une entrée là, sans rien qui les relie : la même caisse
/// de riz se lisait comme une perte dans un magasin et une aubaine dans
/// l'autre, et aucun écran ne savait qu'elle n'avait pas quitté
/// l'entreprise.
///
/// L'en-tête ne porte que ce qui appartient à l'opération — la date, les
/// deux magasins. **Ce qui a bougé reste sur les mouvements**, qui en
/// sont la seule source : recopier ici la référence et la quantité les
/// ferait diverger dès la première correction dans Transactions.
library;

class Transfert {
  final int id;

  /// Date au format ISO `AAAA-MM-JJ`, comme sur les mouvements.
  final String date;

  final int sourceId;
  final int destinationId;

  final String? notes;

  const Transfert({
    required this.id,
    required this.date,
    required this.sourceId,
    required this.destinationId,
    this.notes,
  });

  factory Transfert.fromMap(Map<String, Object?> map) {
    return Transfert(
      id: map['id'] as int,
      date: map['date'] as String,
      sourceId: (map['source_id'] as num).toInt(),
      destinationId: (map['destination_id'] as num).toInt(),
      notes: map['notes'] as String?,
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    return {
      if (includeId) 'id': id,
      'date': date,
      'source_id': sourceId,
      'destination_id': destinationId,
      'notes': notes,
    };
  }
}

/// Une ligne à déplacer : un article et sa quantité.
///
/// Un transfert en porte plusieurs, parce que c'est ce qu'un magasinier
/// fait réellement — il charge une camionnette, pas un article.
class LigneTransfert {
  final String reference;
  final String designation;
  final int quantite;

  const LigneTransfert({
    required this.reference,
    required this.designation,
    required this.quantite,
  });
}

/// Ce qu'un transfert a produit, rendu à l'écran qui l'a demandé.
class ResultatTransfert {
  final int transfertId;

  /// Les lignes écrites, et leur effet.
  final int lignesDeplacees;

  /// Les soldes que ce transfert a fait passer sous zéro dans le magasin
  /// d'origine, comparés à un relevé pris **avant** l'opération.
  ///
  /// Prévenir plutôt que refuser, comme les autres chemins d'écriture :
  /// des marchandises physiquement parties doivent pouvoir être
  /// enregistrées. Mais l'écart ne doit pas passer inaperçu.
  final List<String> negatifs;

  const ResultatTransfert({
    required this.transfertId,
    required this.lignesDeplacees,
    this.negatifs = const [],
  });

  bool get aDesNegatifs => negatifs.isNotEmpty;
}
