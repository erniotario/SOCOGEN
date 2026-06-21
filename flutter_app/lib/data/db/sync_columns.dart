import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// New unique id used as the merge key for `stock_entries`/`stock_outputs`
/// rows, which have no natural unique key.
String newSyncId() => _uuid.v4();

/// Current UTC timestamp in a format that sorts correctly with simple
/// string comparison, used to populate `updated_at` columns.
String nowIso() => DateTime.now().toUtc().toIso8601String();

/// Records that the row identified by [mergeKey] in [table] was deleted,
/// so the deletion can be propagated to a peer on the next sync.
Future<void> recordTombstone(DatabaseExecutor db, String table, String mergeKey) async {
  await db.insert('sync_tombstones', {
    'table_name': table,
    'merge_key': mergeKey,
    'deleted_at': nowIso(),
  });
}
