import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/services/database_integrity_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('DatabaseIntegrityService', () {
    test('does not classify missing sqlite native library as corruption', () {
      const error =
          "Invalid argument(s): Couldn't resolve native function "
          "'sqlite3_initialize' in 'package:sqlite3/src/ffi/libsqlite3.g.dart' : "
          "Failed to load dynamic library 'sqlite3.dll': The specified module "
          'could not be found.';

      expect(
        DatabaseIntegrityService.isDatabaseCorruptionError(error),
        isFalse,
      );
    }, tags: ['regression']);

    for (final code in [11, 26, 267, 523, 779]) {
      test('classifies SQLite damage result $code, not message text', () {
        expect(
          DatabaseIntegrityService.isDatabaseCorruptionError(
            SqliteException(extendedResultCode: code, message: 'inspection'),
          ),
          isTrue,
        );
      });
    }
    for (final code in [1, 5, 6, 8, 10, 13, 14, 23, 261, 266, 520, 1034]) {
      test('SQLite failure $code is not damage', () {
        expect(
          DatabaseIntegrityService.isDatabaseCorruptionError(
            SqliteException(
              extendedResultCode: code,
              message: 'database disk image is malformed',
            ),
          ),
          isFalse,
        );
      });
    }
    test('arbitrary inspection failures never prove corruption', () {
      for (final error in [
        'database disk image is malformed',
        StateError('inspection failed'),
        ArgumentError('libsqlite3 could not load'),
      ]) {
        expect(
          DatabaseIntegrityService.isDatabaseCorruptionError(error),
          isFalse,
        );
      }
    });
  });
}
