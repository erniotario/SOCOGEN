import 'package:erp/core/errors/messages.dart';
import 'package:erp/modules/stock/repositories/store_repository.dart';
import 'package:erp/modules/stock/repositories/transfert_repository.dart';
import 'package:erp/modules/stock/services/stock_service.dart';
import 'package:erp/shared/models/transfert.dart';

/// Déplacer des marchandises d'un magasin à un autre.
///
/// L'opération vaut mieux que les deux mouvements qu'elle produit :
/// c'est le lien entre eux qui dit que la marchandise n'a pas quitté
/// l'entreprise. Sans lui, la même caisse se lit comme une perte ici et
/// une aubaine là.
class TransfertService {
  TransfertService({
    TransfertRepository? transfertRepository,
    StoreRepository? storeRepository,
    StockService? stockService,
  })  : _transferts = transfertRepository ?? TransfertRepository(),
        _magasins = storeRepository ?? StoreRepository(),
        _stock = stockService ?? StockService();

  final TransfertRepository _transferts;
  final StoreRepository _magasins;
  final StockService _stock;

  /// Enregistre un transfert : une sortie du magasin d'origine et une
  /// entrée dans celui d'arrivée, pour chaque ligne.
  ///
  /// Ce qui est refusé, et pourquoi. Un transfert **vers le même
  /// magasin** n'est pas un transfert : il écrirait deux mouvements qui
  /// s'annulent et salirait l'historique pour rien. Une **quantité nulle
  /// ou négative** non plus — une quantité négative inverserait le sens
  /// du transfert sans le dire, ce qui est la pire façon de le faire.
  /// Une **liste vide** n'a rien à enregistrer.
  ///
  /// Ce qui est seulement signalé : un solde passé sous zéro dans le
  /// magasin d'origine. C'est la même politique que les autres chemins
  /// d'écriture — prévenir, pas refuser. De la marchandise physiquement
  /// partie doit pouvoir être enregistrée, et le relevé se prend **avant**
  /// l'opération pour qu'un négatif déjà au dossier ne soit pas mis sur
  /// le dos de celui qui transfère aujourd'hui.
  Future<ResultatTransfert> effectuer({
    required int sourceId,
    required int destinationId,
    required List<LigneTransfert> lignes,
    DateTime? le,
    String? notes,
  }) async {
    if (sourceId == destinationId) {
      throw const ErreurUtilisateur(
        'Le magasin de départ et celui d\'arrivée doivent être différents.',
      );
    }
    if (lignes.isEmpty) {
      throw const ErreurUtilisateur(
        'Ajoutez au moins un article à transférer.',
      );
    }
    for (final ligne in lignes) {
      if (ligne.quantite <= 0) {
        throw ErreurUtilisateur(
          'La quantité à transférer pour ${ligne.reference} doit être '
          'supérieure à 0.',
        );
      }
    }

    final magasins = await _magasins.getAllStores();
    final source = magasins.where((m) => m.id == sourceId).firstOrNull;
    final destination =
        magasins.where((m) => m.id == destinationId).firstOrNull;
    if (source == null || destination == null) {
      throw const ErreurUtilisateur('Magasin introuvable.');
    }

    // Relevé d'avant : ce que ce transfert va creuser, et rien d'autre.
    final negatifs = <String>[];
    for (final ligne in lignes) {
      final avant = await _stock.solde(
        reference: ligne.reference,
        magasinId: sourceId,
      );
      final apres = avant - ligne.quantite;
      if (apres < 0 && avant >= 0) {
        negatifs.add(
          '${ligne.reference} : ${source.name} passe à $apres.',
        );
      }
    }

    final id = await _transferts.creer(
      date: _iso(le ?? DateTime.now()),
      sourceId: sourceId,
      nomSource: source.name,
      destinationId: destinationId,
      nomDestination: destination.name,
      lignes: lignes,
      notes: notes,
    );

    return ResultatTransfert(
      transfertId: id,
      lignesDeplacees: lignes.length,
      negatifs: negatifs,
    );
  }

  Future<List<({Transfert transfert, String source, String destination, int lignes})>>
      lister({int? limite}) => _transferts.getAll(limite: limite);

  Future<List<LigneTransfert>> lignesDe(int transfertId) =>
      _transferts.lignesDe(transfertId);

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
