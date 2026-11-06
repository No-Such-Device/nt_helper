import 'package:nt_helper/db/database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reset application data through the live connection, never by unlinking it.
class DatabaseResetService {
  static Future<void> resetAll(AppDatabase database) async {
    await database.transaction(() async {
      await database.customStatement('PRAGMA defer_foreign_keys=ON');
      for (final table in database.allTables) {
        await database.delete(table).go();
      }
    });
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.clear()) {
      throw StateError('Could not clear app preferences');
    }
  }
}
