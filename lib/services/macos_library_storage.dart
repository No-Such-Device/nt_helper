import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/services/database_integrity_service.dart';
import 'package:nt_helper/services/macos_storage_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

const libraryFileName = 'nt_helper_db.sqlite';
const _journals = ['-wal', '-shm', '-journal'];

enum StorageFailureKind {
  busy,
  access,
  io,
  native,
  uncertain,
  unsupportedSchema,
  damaged,
}

final class StorageFailure implements Exception {
  const StorageFailure(this.kind, this.message, [this.cause, this.diagnostics]);
  final StorageFailureKind kind;
  final String message;
  final Object? cause;
  final String? diagnostics;
  @override
  String toString() =>
      'Storage ${kind.name}: $message${cause == null ? '' : ' ($cause)'}'
      '${diagnostics == null ? '' : '\n\n$diagnostics'}';
}

/// Fault seam shared by deterministic faults and disposable process-death tests.
/// Each persistent operation is bracketed; throwing never deletes failed work.
typedef StorageCheckpoint = Future<void> Function(String boundary);

enum LibraryRecovery { repaired, freshAfterDamage }

/// Open the saved path without CREATE. Historic file identities are diagnostic
/// evidence after a failed open, not a prerequisite for trying SQLite.
/// No legacy access is needed.
final class SelectedLibrary {
  SelectedLibrary._(
    this.file,
    this.identity,
    this.journalIdentity,
    this.attempt, [
    this.recovery,
  ]);
  final File file;
  final String identity;
  final String journalIdentity;
  final String attempt;
  final LibraryRecovery? recovery;

  StorageFailure _openingFailure(Object error, String operation) {
    final failure = classifyStorageFailure(error, operation);
    if (failure.diagnostics != null) return failure;
    final report = StringBuffer('Library open attempt: $operation\n');
    for (final suffix in ['', ..._journals]) {
      final path = '${file.path}$suffix';
      report.writeln('File: $path');
      try {
        final actual = MacosStorageIo.identity(path);
        report.writeln('  Observed identity: ${actual ?? 'missing'}');
        if (actual != null) {
          final stat = FileStat.statSync(path);
          report.writeln(
            '  Size: ${stat.size} bytes; mode: ${stat.modeString()}',
          );
        }
        final expected = suffix.isEmpty
            ? identity
            : suffix == '-journal'
            ? journalIdentity
            : null;
        if (expected != null) {
          report.writeln('  Recorded identity: $expected');
          report.writeln('  Identity matches: ${actual == expected}');
        }
      } catch (inspectionError) {
        report.writeln('  Could not inspect: $inspectionError');
      }
    }
    return StorageFailure(
      failure.kind,
      failure.message,
      failure.cause,
      report.toString(),
    );
  }

  Database openRaw() {
    try {
      final raw = sqlite3.open(file.path, mode: OpenMode.readWrite);
      try {
        raw.execute(
          'PRAGMA journal_mode=PERSIST; PRAGMA fullfsync=ON; PRAGMA synchronous=FULL',
        );
        return raw;
      } catch (_) {
        raw.close();
        rethrow;
      }
    } catch (error) {
      throw _openingFailure(error, 'SQLite could not open the saved library');
    }
  }

  Future<AppDatabase> open({StorageCheckpoint? checkpoint}) async {
    final raw = openRaw();
    final app = AppDatabase.withExecutor(
      NativeDatabase.opened(raw),
      storageCheckpoint: checkpoint,
    );
    try {
      _checkVersion(raw, app);
      await _querySchema(app);
      final damage = DatabaseIntegrityService.inspect(raw);
      if (damage != null) {
        throw StorageFailure(StorageFailureKind.damaged, damage);
      }
      return app;
    } catch (error) {
      await app.close();
      throw _openingFailure(error, 'SQLite could not read the saved library');
    }
  }
}

/// One macOS selection transaction. Every attempt uses a new isolated work
/// directory, reserved by a durable receipt *before* that directory is created.
/// Failed work is never overwritten, even when known. Complete records are
/// published with atomic no-replace links and directory fsync; interrupted temp
/// records are retained but cannot confer authority. selected.json is immutable.
final class MacosLibraryStorage {
  MacosLibraryStorage({
    required this.directory,
    required this.documentsProvider,
    this.checkpoint,
  });
  final Directory directory;
  final Future<Directory> Function() documentsProvider;
  final StorageCheckpoint? checkpoint;
  Directory get _control => Directory(p.join(directory.path, '.storage-v1'));

  Future<void> _at(String name) async {
    await checkpoint?.call(name);
  }

  Future<T> _effect<T>(String name, Future<T> Function() action) async {
    await _at('before:$name');
    final result = await action();
    await _at('after:$name');
    return result;
  }

  Future<SelectedLibrary> prepare() async {
    MacosStorageLease? lease;
    final locked = <Database>[];
    final files = _SourceFiles();
    try {
      await _effect('directory', () async {
        _ensureDirectory(directory);
      });
      await _effect('control', () async {
        _ensureDirectory(_control);
      });
      await _effect('coordination', () async {
        lease = MacosStorageIo.lock(p.join(_control.path, 'lock'));
        MacosStorageIo.sync(_control.path);
      });
      final selected = _readSelection();
      if (selected != null) {
        try {
          await _effect('open', () async {
            final app = await selected.open(checkpoint: checkpoint);
            await app.close();
          });
          return selected;
        } catch (error) {
          // Only an actual failed open/read can lead to recovery inspection.
          // Missing files, access errors and busy databases never authorize a
          // replacement or fallback to the old Documents copy.
          if (!_positiveDamage(error)) rethrow;
          final bool damaged;
          try {
            damaged = await _effect(
              'inspect-selected',
              () async => _inspectSource(selected.file.path, files),
            );
          } catch (inspectionError) {
            throw selected._openingFailure(
              StorageFailure(
                StorageFailureKind.uncertain,
                'The library could not be opened and safe recovery could not be established.',
                '$error\nRecovery inspection: $inspectionError',
              ),
              'Recovery inspection after a failed SQLite open',
            );
          }
          if (!damaged) rethrow;
        }
      }

      // Selected damage never reintroduces a Documents prerequisite. A recovery
      // successor uses the same owned work and no-replace selection protocol.
      final documents = selected == null ? await documentsProvider() : null;
      final paths = selected != null
          ? [selected.file.path]
          : [
              p.join(documents!.path, libraryFileName),
              p.join(documents.path, 'nt_helper', libraryFileName),
              p.join(directory.path, libraryFileName),
            ];
      final inventory = _inventory(paths);
      final sources = inventory.entries
          .where((e) => e.value != null)
          .map((e) => e.key)
          .toList();
      if (selected == null) _checkReceipts(inventory, files);

      final attempt = const Uuid().v4();
      final work = Directory(p.join(_control.path, 'work-$attempt'));
      await _effect('reservation', () async {
        await _publish('attempt-$attempt.json', {
          'version': 1,
          'attempt': attempt,
          'work': p.basename(work.path),
          'sources': inventory,
          'recovery': {
            for (final source in sources)
              source: _recoveryReceipt(source, files),
          },
        });
      });
      await _effect('work', () async {
        MacosStorageIo.reserveDirectory(work.path);
        MacosStorageIo.sync(_control.path);
      });

      // Retain main AND sidecars before sqlite3.open can recover/checkpoint or
      // remove anything. A second retained capture under exclusion follows.
      for (var i = 0; i < sources.length; i++) {
        final source = sources[i];
        await _effect('retain-$i', () async {
          _retain(source, work, 'original-$i', files);
        });
        await _effect('exclude-$i', () async {
          try {
            final raw = sqlite3.open(source, mode: OpenMode.readWrite);
            locked.add(raw);
            raw.execute('PRAGMA busy_timeout=0');
            // RESERVED in rollback mode, WAL write lock in WAL mode: excludes
            // future writers. A failed lock/inspection is not damage authority.
            raw.execute('BEGIN IMMEDIATE');
          } on SqliteException catch (error) {
            if (DatabaseIntegrityService.isDatabaseCorruptionError(error)) {
              throw StorageFailure(
                StorageFailureKind.uncertain,
                'Cannot establish library authority through coherent exclusive inspection: $source; all files are retained',
                error,
              );
            }
            rethrow;
          }
          if (MacosStorageIo.identity(source) != inventory[source]) {
            throw const StorageFailure(
              StorageFailureKind.uncertain,
              'Source identity changed while acquiring exclusion',
            );
          }
        });
        await _effect('retain-locked-$i', () async {
          _retain(source, work, 'locked-$i', files);
        });
      }
      _requireInventory(paths, inventory);
      final seals = {
        for (final source in sources) source: _seal(source, files),
      };
      String? expected;
      File? destination;
      LibraryRecovery? recovery;
      for (var i = 0; i < sources.length; i++) {
        final copy = File(
          p.join(work.path, i == 0 ? libraryFileName : 'comparison-$i.sqlite'),
        );
        final damaged = await _effect(
          'inspect-$i',
          () async => _inspectSource(sources[i], files),
        );
        var transferSource = sources[i];
        if (damaged) {
          if (sources.length != 1) {
            throw const StorageFailure(
              StorageFailureKind.uncertain,
              'Damage in competing unselected stores cannot establish sole authority; all files are retained',
            );
          }
          final repaired = await _effect('repair', () async {
            _retain(sources[i], work, 'repair', files);
            final repair = File(p.join(work.path, 'repair', libraryFileName));
            return _repair(repair, checkpoint: checkpoint);
          });
          if (!repaired) {
            recovery = LibraryRecovery.freshAfterDamage;
            break; // Only confirmed source damage AND failed safe repair.
          }
          recovery = LibraryRecovery.repaired;
          transferSource = p.join(work.path, 'repair', libraryFileName);
        }
        late final String semantic;
        try {
          await _effect('transfer-$i', () async {
            await _backup(
              transferSource,
              copy,
              () => _at('during:transfer-$i'),
            );
            MacosStorageIo.sync(copy.path);
            MacosStorageIo.sync(work.path);
          });
          semantic = await _effect(
            'schema-$i',
            () => _validate(copy, checkpoint: checkpoint),
          );
        } catch (error) {
          if (!_positiveDamage(error)) rethrow;
          throw StorageFailure(
            StorageFailureKind.uncertain,
            'Isolated transfer or validation failed; source damage was not established by this failure',
            error,
          );
        }
        if (expected != null && expected != semantic) {
          throw const StorageFailure(
            StorageFailureKind.uncertain,
            'Unselected libraries are not completely equivalent; all candidates have been retained',
          );
        }
        expected = semantic;
        destination ??= copy;
      }
      if (destination == null) {
        destination = File(p.join(work.path, libraryFileName));
        await _effect('initialize', () async {
          final raw = sqlite3.open(destination!.path);
          raw.close();
          MacosStorageIo.sync(destination.path);
          MacosStorageIo.sync(work.path);
        });
        await _effect(
          'schema-0',
          () => _validate(destination!, allowNew: true, checkpoint: checkpoint),
        );
      }
      await _effect('validation', () async {
        _requireInventory(paths, inventory);
        for (final source in sources) {
          if (_seal(source, files) != seals[source]) {
            throw const StorageFailure(
              StorageFailureKind.uncertain,
              'Source recovery data changed under exclusion; Retry to reobserve',
            );
          }
        }
        // All stores used for the new selection use retained rollback journals.
        // The journal inode is part of authority; its loss cannot silently look
        // like a clean main file. No source is switched out of WAL mode.
        final raw = sqlite3.open(destination!.path, mode: OpenMode.readWrite);
        try {
          raw.execute('PRAGMA journal_mode=PERSIST');
          raw.execute('PRAGMA synchronous=FULL; PRAGMA fullfsync=ON');
          final version = raw.select('PRAGMA user_version').first.values.first;
          raw.execute('PRAGMA user_version=$version');
        } finally {
          raw.close();
        }
        MacosStorageIo.sync(destination.path);
        MacosStorageIo.sync('${destination.path}-journal');
        MacosStorageIo.sync(work.path);
      });
      final result = SelectedLibrary._(
        destination,
        MacosStorageIo.identity(destination.path)!,
        MacosStorageIo.identity('${destination.path}-journal')!,
        attempt,
        recovery,
      );
      await _effect('selection', () async {
        _requireInventory(paths, inventory);
        for (final source in sources) {
          if (_seal(source, files) != seals[source]) {
            throw const StorageFailure(
              StorageFailureKind.uncertain,
              'Source changed before durable cutover',
            );
          }
        }
        await _publish(
          selected == null
              ? 'selected.json'
              : 'selected-${selected.attempt}.json',
          {
            'version': 1,
            if (selected != null) 'predecessor': selected.attempt,
            if (recovery != null) 'recovery': recovery.name,
            'file': p.relative(result.file.path, from: _control.path),
            'identity': result.identity,
            'journalIdentity': result.journalIdentity,
            'attempt': attempt,
          },
        );
      });
      // Cutover is durable before exclusion is released. Never keep a lifetime
      // Documents lease, and never consult it on the selected path.
      _release(locked);
      files.close();
      await _effect('open', () async {
        final app = await result.open(checkpoint: checkpoint);
        await app.close();
      });
      return result;
    } catch (error) {
      throw classifyStorageFailure(error, 'Library selection did not complete');
    } finally {
      _release(locked);
      files.close();
      lease?.close();
    }
  }

  SelectedLibrary? _readSelection() {
    var path = p.join(_control.path, 'selected.json');
    SelectedLibrary? previous;
    final seen = <String>{};
    while (MacosStorageIo.identity(path) != null) {
      final record = _readRecord(path);
      final relative = record['file'];
      final attempt = record['attempt'];
      if (relative is! String ||
          attempt is! String ||
          !RegExp(r'^[a-f0-9-]{36}$').hasMatch(attempt) ||
          relative != p.join('work-$attempt', libraryFileName) ||
          record['identity'] is! String ||
          record['journalIdentity'] is! String) {
        throw const StorageFailure(
          StorageFailureKind.uncertain,
          'Malformed selected authority',
        );
      }
      final receipt = _readRecord(
        p.join(_control.path, 'attempt-$attempt.json'),
      );
      if (receipt['attempt'] != attempt || receipt['work'] != 'work-$attempt') {
        throw const StorageFailure(
          StorageFailureKind.uncertain,
          'Contradictory selected authority',
        );
      }
      final recoveryName = record['recovery'];
      final recovery = recoveryName == null
          ? null
          : LibraryRecovery.values
                .where((r) => r.name == recoveryName)
                .firstOrNull;
      if (!seen.add(attempt) ||
          (recoveryName != null && recovery == null) ||
          record['predecessor'] != previous?.attempt ||
          (previous != null &&
              (receipt['sources'] as Map?)?[previous.file.path] is! String)) {
        throw const StorageFailure(
          StorageFailureKind.uncertain,
          'Contradictory recovery selection authority',
        );
      }
      previous = SelectedLibrary._(
        File(p.join(_control.path, relative)),
        record['identity'] as String,
        record['journalIdentity'] as String,
        attempt,
        recovery,
      );
      path = p.join(_control.path, 'selected-$attempt.json');
    }
    return previous;
  }

  void _checkReceipts(Map<String, String?> inventory, _SourceFiles files) {
    for (final entry in _control.listSync()) {
      final name = p.basename(entry.path);
      if (name.startsWith('attempt-') && name.endsWith('.json')) {
        final record = _readRecord(entry.path);
        final attempt = record['attempt'];
        if (attempt is! String ||
            !RegExp(r'^[a-f0-9-]{36}$').hasMatch(attempt) ||
            name != 'attempt-$attempt.json' ||
            record['work'] != 'work-$attempt' ||
            record['sources'] is! Map ||
            record['recovery'] is! Map) {
          throw const StorageFailure(
            StorageFailureKind.uncertain,
            'Malformed migration ownership history',
          );
        }
        for (final entry in (record['recovery'] as Map).entries) {
          final source = entry.key;
          final previous = entry.value;
          if (source is! String ||
              !inventory.containsKey(source) ||
              previous is! Map ||
              previous['walBytes'] is! int ||
              previous['main'] is! String ||
              (previous['walSemantics'] != null &&
                  previous['walSemantics'] is! String)) {
            throw const StorageFailure(
              StorageFailureKind.uncertain,
              'Malformed migration recovery history',
            );
          }
          if ((previous['walBytes'] as int) > 32 &&
              MacosStorageIo.identity('$source-wal') == null &&
              MacosStorageIo.identity(source) != null) {
            final main = files.read(source);
            // A FULL checkpoint may leave a nonempty WAL that disappears on
            // normal last-close without changing main. Compare the coherent
            // recovery evidence, not WAL length, before declaring data lost.
            if (sha256.convert(main).toString() == previous['main'] &&
                (previous['walSemantics'] == null ||
                    _recoverySemantics(main) != previous['walSemantics'])) {
              throw const StorageFailure(
                StorageFailureKind.uncertain,
                'Previously observed WAL recovery data is missing and completeness cannot be established; restore required recovery data and Retry',
              );
            }
          }
        }
        if (jsonEncode(record['sources']) != jsonEncode(inventory)) {
          throw const StorageFailure(
            StorageFailureKind.uncertain,
            'A previous migration source identity is missing or replaced; retained work cannot establish authority for an independent library',
          );
        }
      } else if (name.startsWith('work-')) {
        final receipt = p.join(
          _control.path,
          'attempt-${name.substring(5)}.json',
        );
        if (MacosStorageIo.identity(receipt) == null) {
          throw const StorageFailure(
            StorageFailureKind.uncertain,
            'Unexplained migration work; preserved without replacement',
          );
        }
      }
    }
  }

  Future<void> _publish(String name, Map<String, Object?> payload) async {
    final body = jsonEncode(payload);
    final temp = p.join(_control.path, 'pending-${const Uuid().v4()}');
    final bytes = utf8.encode(
      jsonEncode({
        'body': body,
        'witness': p.basename(temp),
        'sha256': sha256.convert(utf8.encode(body)).toString(),
      }),
    );
    // A kill after the temp file is written but before its atomic publication
    // is explicitly tested. Such a temp is never parsed as authority.
    final kind = name.startsWith('selected') ? 'selection' : 'reservation';
    await MacosStorageIo.publish(
      temp,
      p.join(_control.path, name),
      bytes,
      (point) => _at('$point:$kind-record'),
    );
  }
}

Map<String, dynamic> _readRecord(String path) {
  try {
    MacosStorageIo.requireFile(path);
    final envelope = jsonDecode(File(path).readAsStringSync()) as Map;
    final body = envelope['body'] as String;
    final witness = envelope['witness'] as String;
    if (!RegExp(r'^pending-[a-f0-9-]{36}$').hasMatch(witness) ||
        MacosStorageIo.identity(path) !=
            MacosStorageIo.identity(p.join(File(path).parent.path, witness))) {
      throw const StorageFailure(
        StorageFailureKind.uncertain,
        'Storage authority was replaced or lost its durable witness',
      );
    }
    if (sha256.convert(utf8.encode(body)).toString() != envelope['sha256']) {
      throw const FormatException();
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    if (data['version'] != 1) throw const FormatException();
    return data;
  } on FileSystemException {
    rethrow;
  } catch (error) {
    throw StorageFailure(
      StorageFailureKind.uncertain,
      'Malformed storage authority; retained',
      error,
    );
  }
}

void _ensureDirectory(Directory directory) {
  final identity = MacosStorageIo.identity(directory.path);
  if (identity != null && !identity.startsWith('16384:')) {
    throw StorageFailure(
      StorageFailureKind.uncertain,
      'Expected storage directory: ${directory.path}',
    );
  }
  if (identity == null) {
    directory.createSync(recursive: true);
    MacosStorageIo.sync(directory.parent.path);
  }
  directory
      .listSync(); // Prove access; existsSync alone hides denied inventory.
}

Map<String, String?> _inventory(List<String> paths) {
  final result = <String, String?>{};
  for (final path in paths) {
    // Prove ancestor access and reject symlinks, including competing locations.
    var parent = File(path).parent;
    while (MacosStorageIo.identity(parent.path) == null) {
      parent = parent.parent;
    }
    _ensureDirectory(parent);
    final identity = MacosStorageIo.identity(path);
    if (identity != null) MacosStorageIo.requireFile(path);
    result[path] = identity;
    for (final suffix in _journals) {
      final sidecar = '$path$suffix';
      if (MacosStorageIo.identity(sidecar) != null) {
        MacosStorageIo.requireFile(sidecar);
        if (identity == null ||
            (suffix == '-shm' &&
                MacosStorageIo.identity('$path-wal') == null)) {
          throw StorageFailure(
            StorageFailureKind.uncertain,
            'Orphan or missing indispensable journal: $sidecar',
          );
        }
      }
    }
  }
  return result;
}

void _requireInventory(List<String> paths, Map<String, String?> expected) {
  if (jsonEncode(_inventory(paths)) != jsonEncode(expected)) {
    throw const StorageFailure(
      StorageFailureKind.uncertain,
      'Candidate inventory changed; Retry after writers settle',
    );
  }
}

void _retain(String source, Directory work, String name, _SourceFiles files) {
  final before = _seal(source, files);
  final retained = Directory(p.join(work.path, name))..createSync();
  for (final suffix in ['', ..._journals]) {
    final path = '$source$suffix';
    if (MacosStorageIo.identity(path) != null) {
      final copy = File(p.join(retained.path, '$libraryFileName$suffix'));
      copy.writeAsBytesSync(files.read(path), flush: true);
      MacosStorageIo.sync(copy.path);
    }
  }
  MacosStorageIo.sync(retained.path);
  MacosStorageIo.sync(work.path);
  if (_seal(source, files) != before) {
    throw const StorageFailure(
      StorageFailureKind.uncertain,
      'Source changed while preserving untouched recovery data; Retry after writers settle',
    );
  }
}

Map<String, Object?> _recoveryReceipt(String source, _SourceFiles files) {
  final before = _seal(source, files);
  final main = files.read(source);
  final wal = MacosStorageIo.identity('$source-wal') == null
      ? null
      : files.read('$source-wal');
  String? semantic;
  if (wal != null && wal.length > 32) {
    try {
      semantic = _recoverySemantics(main, wal);
    } catch (error) {
      // Pre-exclusion bytes are retention evidence, never damage authority.
      // A damaged image can still be retained; missing its WAL later blocks.
      if (!_positiveDamage(error)) rethrow;
    }
  }
  final recovery = {
    'main': sha256.convert(main).toString(),
    'walBytes': wal?.length ?? 0,
    'walSemantics': ?semantic,
  };
  if (_seal(source, files) != before) {
    throw const StorageFailure(
      StorageFailureKind.uncertain,
      'Source changed while recording recovery evidence; Retry after writers settle',
    );
  }
  return recovery;
}

/// Let SQLite interpret committed WAL frames on private, memory-only copies.
/// Exclusive mode needs no shared WAL index. No original is opened, checkpointed
/// or closed, and the digest is durable with the very first ownership receipt.
String _recoverySemantics(Uint8List main, [Uint8List? wal]) {
  final image = _RecoveryImage({'': main, '-wal': ?wal});
  try {
    final damage = DatabaseIntegrityService.inspect(image.raw);
    if (damage != null) {
      throw StorageFailure(StorageFailureKind.damaged, damage);
    }
    return _semantics(image.raw);
  } finally {
    image.close();
  }
}

final class _RecoveryImage {
  _RecoveryImage(Map<String, Uint8List> bytes) {
    for (final entry in bytes.entries) {
      final opened = vfs.xOpen(
        Sqlite3Filename('/library${entry.key}'),
        SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE,
      );
      opened.file.xWrite(entry.value, 0);
      opened.file.xClose();
    }
    sqlite3.registerVirtualFileSystem(vfs);
    Database? opened;
    try {
      opened = sqlite3.open(
        '/library',
        vfs: vfs.name,
        mode: OpenMode.readWrite,
      );
      opened.execute('PRAGMA locking_mode=EXCLUSIVE');
      raw = opened;
    } catch (_) {
      opened?.close();
      sqlite3.unregisterVirtualFileSystem(vfs);
      rethrow;
    }
  }
  final vfs = InMemoryFileSystem(name: 'nt-recovery-${const Uuid().v4()}');
  late final Database raw;
  void close() {
    raw.close();
    sqlite3.unregisterVirtualFileSystem(vfs);
  }
}

bool _positiveDamage(Object error) =>
    (error is StorageFailure && error.kind == StorageFailureKind.damaged) ||
    DatabaseIntegrityService.isDatabaseCorruptionError(error);

/// Called again under exclusion before damage can authorize anything. Opening
/// these private bytes cannot checkpoint, repair or remove original sidecars.
Future<bool> _inspectSource(String source, _SourceFiles files) async {
  final before = _seal(source, files);
  final image = _RecoveryImage({
    '': files.read(source),
    for (final suffix in ['-wal', '-journal'])
      if (MacosStorageIo.identity('$source$suffix') != null)
        suffix: files.read('$source$suffix'),
  });
  final app = AppDatabase.forTesting(
    NativeDatabase.opened(image.raw, closeUnderlyingOnClose: false),
  );
  try {
    try {
      _checkVersion(image.raw, app);
    } on SqliteException catch (error) {
      if (!DatabaseIntegrityService.isDatabaseCorruptionError(error)) rethrow;
      throw StorageFailure(
        StorageFailureKind.uncertain,
        'Cannot establish a supported library schema; originals are retained',
        error,
      );
    }
    bool damaged;
    try {
      damaged = DatabaseIntegrityService.inspect(image.raw) != null;
    } on SqliteException catch (error) {
      if (!DatabaseIntegrityService.isDatabaseCorruptionError(error)) rethrow;
      damaged = true;
    }
    if (damaged) {
      // Prove this is a supported library, not an unknown partial or a random
      // file. AppDatabase owns supported upgrades; LIMIT 0 validates the full
      // schema without reading damaged table/index pages or losing rows.
      try {
        await _querySchema(app, limit: 0);
      } on SqliteException catch (error) {
        if (!DatabaseIntegrityService.isDatabaseCorruptionError(error)) rethrow;
        throw StorageFailure(
          StorageFailureKind.uncertain,
          'Cannot validate the complete supported schema; originals are retained',
          error,
        );
      }
    }
    if (_seal(source, files) != before) {
      throw const StorageFailure(
        StorageFailureKind.uncertain,
        'Source changed during isolated inspection; Retry after writers settle',
      );
    }
    return damaged;
  } finally {
    await app.close();
    image.close();
  }
}

/// Conservative repair: rebuild indexes only if complete logical contents,
/// schema, relationships and sequence state can be read and remain identical.
/// Unreadable/lost rows are not a successful repair. Never repair in place.
Future<bool> _repair(File file, {StorageCheckpoint? checkpoint}) async {
  final raw = sqlite3.open(file.path, mode: OpenMode.readWrite);
  try {
    final before = _semantics(raw);
    await checkpoint?.call('before:reindex');
    raw.execute('REINDEX');
    await checkpoint?.call('after:reindex');
    if (DatabaseIntegrityService.inspect(raw) != null ||
        raw.select('PRAGMA foreign_key_check').isNotEmpty ||
        _semantics(raw) != before) {
      return false;
    }
  } catch (error) {
    // With damage already proven, a uniqueness violation rebuilding an index
    // means repair cannot preserve both the rows and the supported constraints.
    final incompatibleRows = error is SqliteException && error.resultCode == 19;
    if (!_positiveDamage(error) && !incompatibleRows) rethrow;
    return false;
  } finally {
    raw.close();
  }
  await _validate(file, checkpoint: checkpoint);
  return true;
}

Future<void> _backup(
  String source,
  File destination,
  Future<void> Function() during,
) async {
  final reader = sqlite3.open(source, mode: OpenMode.readOnly);
  Database? target;
  try {
    target = sqlite3.open(destination.path);
    await for (final _ in reader.backup(target, nPage: 8)) {
      await during();
    }
  } finally {
    target?.close();
    reader.close();
  }
}

void _checkVersion(Database raw, AppDatabase app, {bool allowNew = false}) {
  final version = raw.select('PRAGMA user_version').first.values.first as int;
  if (version == 0 && !allowNew) {
    throw const StorageFailure(
      StorageFailureKind.uncertain,
      'Unknown empty or unversioned historical target',
    );
  }
  if (version > app.schemaVersion || version < 0) {
    throw StorageFailure(
      StorageFailureKind.unsupportedSchema,
      'Unsupported schema version $version',
    );
  }
}

String _seal(String path, _SourceFiles files) => jsonEncode([
  for (final suffix in ['', '-wal', '-journal'])
    if (MacosStorageIo.identity('$path$suffix') case final String identity)
      [suffix, identity, sha256.convert(files.read('$path$suffix')).toString()],
]);

// Hold every auxiliary source fd until SQLite has released its exclusion.
// Opening/closing main or SHM with dart:io under a SQLite lock would silently
// drop POSIX fcntl locks, even though SQLite still believes it owns them.
final class _SourceFiles {
  final _reads = <String, MacosStorageRead>{};
  Uint8List read(String path) {
    final identity = MacosStorageIo.identity(path);
    if (identity == null) {
      throw StorageFailure(
        StorageFailureKind.uncertain,
        'Source recovery data disappeared: $path',
      );
    }
    final key = '$path|$identity';
    final reader = _reads.putIfAbsent(key, () => MacosStorageIo.openRead(path));
    if (MacosStorageIo.identity(path) != identity) {
      throw const StorageFailure(
        StorageFailureKind.uncertain,
        'Source changed while acquiring read access',
      );
    }
    return reader.read();
  }

  void close() {
    for (final reader in _reads.values) {
      reader.close();
    }
    _reads.clear();
  }
}

Future<String> _validate(
  File file, {
  bool allowNew = false,
  StorageCheckpoint? checkpoint,
}) async {
  final raw = sqlite3.open(file.path, mode: OpenMode.readWrite);
  final app = AppDatabase.withExecutor(
    NativeDatabase.opened(raw),
    storageCheckpoint: checkpoint,
  );
  try {
    _checkVersion(raw, app, allowNew: allowNew);
    if (raw
        .select('PRAGMA integrity_check')
        .any((r) => r.values.first != 'ok')) {
      throw const StorageFailure(
        StorageFailureKind.damaged,
        'SQLite reports damaged library data',
      );
    }
    await _querySchema(app);
    return _semantics(raw);
  } finally {
    await app.close();
  }
}

Future<void> _querySchema(AppDatabase app, {int limit = 1}) async {
  // Forces real opening and supported migrations; also checks every supported
  // table/column instead of using a lazy constructor or PRAGMA-only readiness.
  for (final table in app.allTables) {
    final columns = table.$columns.map((c) => _quote(c.$name)).join(',');
    await app
        .customSelect(
          'SELECT $columns FROM ${_quote(table.actualTableName)} LIMIT $limit',
        )
        .get();
  }
  if (limit != 0) await app.select(app.algorithms).get();
}

String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';
Object? _value(Object? value) =>
    value is Uint8List ? {'blob': base64Encode(value)} : value;

/// Canonical complete logical content, including duplicates and sqlite_sequence.
/// Supported upgrades run first. Schema metadata includes defaults, keys, FKs,
/// indexes, views and triggers; no file-size/count/visible-preset shortcut.
String _semantics(Database raw) {
  final objects = raw.select(
    "SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE name NOT LIKE 'sqlite_autoindex_%' ORDER BY type,name",
  );
  final output = <Object?>[];
  for (final object in objects) {
    final name = object['name'] as String;
    if (object['type'] == 'table') {
      final columns =
          raw
              .select('PRAGMA table_info(${_quote(name)})')
              .map(
                (r) => [
                  r['name'],
                  r['type'],
                  r['notnull'],
                  r['dflt_value'],
                  r['pk'],
                ],
              )
              .toList()
            ..sort((a, b) => (a.first as String).compareTo(b.first as String));
      final columnNames = columns
          .map((r) => _quote(r.first as String))
          .join(',');
      final rows =
          raw
              .select('SELECT $columnNames FROM ${_quote(name)}')
              .map((r) => jsonEncode(r.values.map(_value).toList()))
              .toList()
            ..sort();
      final keys =
          raw
              .select('PRAGMA foreign_key_list(${_quote(name)})')
              .map((r) => jsonEncode(r.values.toList()))
              .toList()
            ..sort();
      final indexes = <String>[];
      for (final index in raw.select('PRAGMA index_list(${_quote(name)})')) {
        indexes.add(
          jsonEncode([
            index['unique'],
            index['origin'],
            index['partial'],
            raw
                .select('PRAGMA index_info(${_quote(index['name'] as String)})')
                .map((r) => r['name'])
                .toList(),
          ]),
        );
      }
      indexes.sort();
      output.add([name, columns, keys, indexes, rows]);
    } else {
      output.add(object.values.toList());
    }
  }
  output.add(raw.select('PRAGMA user_version').first.values.toList());
  output.add(raw.select('PRAGMA application_id').first.values.toList());
  return sha256.convert(utf8.encode(jsonEncode(output))).toString();
}

void _release(List<Database> locked) {
  for (final raw in locked.reversed) {
    raw.close();
  }
  locked.clear();
}

StorageFailure classifyStorageFailure(Object error, String operation) {
  if (error is StorageFailure) return error;
  if (error is SqliteException) {
    final kind = switch (error.resultCode & 0xff) {
      5 || 6 => StorageFailureKind.busy,
      11 || 26 when DatabaseIntegrityService.isDatabaseCorruptionError(error) =>
        StorageFailureKind.damaged,
      8 || 14 || 23 => StorageFailureKind.access,
      _ => StorageFailureKind.io,
    };
    return StorageFailure(kind, operation, error);
  }
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    return StorageFailure(
      error.message.contains('busy')
          ? StorageFailureKind.busy
          : code == 1 || code == 13
          ? StorageFailureKind.access
          : error.message.contains('Unsupported')
          ? StorageFailureKind.uncertain
          : StorageFailureKind.io,
      operation,
      error,
    );
  }
  return StorageFailure(StorageFailureKind.native, operation, error);
}
