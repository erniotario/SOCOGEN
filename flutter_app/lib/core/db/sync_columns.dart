import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:erp/core/auth/session_courante.dart';

const _uuid = Uuid();

/// New unique id used as the merge key for `stock_entries`/`stock_outputs`
/// rows, which have no natural unique key.
String newSyncId() => _uuid.v4();

/// Identity minted for a business the first time two of its devices sync.
/// Distinct from [newSyncId] only in intent -- one names a row, this names
/// the whole database -- but naming it separately keeps the two from being
/// confused at the call site.
String newTenantId() => _uuid.v4();

/// Current UTC timestamp in a format that sorts correctly with simple
/// string comparison, used to populate `updated_at` columns.
String nowIso() => DateTime.now().toUtc().toIso8601String();

/// Qui écrit, et quand — à poser sur toute ligne de registre créée.
///
/// L'auteur se lit sur la session en cours plutôt que de se recevoir en
/// argument : c'est un fait sur qui est connecté, pas un choix de
/// l'appelant. Aucun formulaire ne peut donc signer au nom d'un autre.
///
/// `created_at` est l'instant de l'écriture, distinct de la `date` du
/// mouvement : un registre doit pouvoir dire qu'une ligne datée du 1er a
/// été saisie le 5.
///
/// Nul est une valeur normale : hors session, la ligne n'a pas d'auteur,
/// et c'est plus exact que d'en désigner un.
Map<String, Object?> attribution() => {
      'created_by': SessionCourante.instance.utilisateurId,
      'created_at': nowIso(),
    };

/// Records that the row identified by [mergeKey] in [table] was deleted,
/// so the deletion can be propagated to a peer on the next sync.
Future<void> recordTombstone(DatabaseExecutor db, String table, String mergeKey) async {
  await db.insert('sync_tombstones', {
    'table_name': table,
    'merge_key': mergeKey,
    'deleted_at': nowIso(),
  });
}
