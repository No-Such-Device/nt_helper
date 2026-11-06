import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/services/startup_storage_opener.dart';
import 'package:nt_helper/services/startup_log_service.dart';
import 'package:nt_helper/services/library_storage.dart';

/// One observable startup lifecycle: settled storage retries, then once-only
/// service activation. Closing synchronously invalidates every pending result.
class StartupController extends ChangeNotifier {
  StartupController({
    required this.open,
    this.activationSteps = const [],
    this.canSelectLegacyDirectory,
    this.libraryLocation,
  });

  final Future<OpenedStartupLibrary> Function({
    bool selectLegacyDirectory,
    File? importSource,
    bool startFresh,
  })
  open;
  final List<Future<void> Function(AppDatabase)> activationSteps;
  final bool Function()? canSelectLegacyDirectory;
  final String? Function()? libraryLocation;
  Future<void>? _pending;
  Future<void>? _closing;
  OpenedStartupLibrary? _library;
  bool _closed = false;
  bool _activationStarted = false;
  bool _ready = false;
  Object? failure;

  bool get busy => _pending != null;
  bool get closed => _closed;
  bool get ready => _ready && !_closed;
  bool get canRetry => !_closed && !_activationStarted;
  bool get canSelectAccess =>
      canRetry && (canSelectLegacyDirectory?.call() ?? false);
  AppDatabase get database => _library!.database;
  String? get location => _library?.location ?? libraryLocation?.call();
  bool get canImport => canRetry && failure is LibraryImportException;

  Future<void> retry({
    bool selectLegacyDirectory = false,
    File? importSource,
    bool startFresh = false,
  }) {
    if (_pending != null) return _pending!;
    if (!canRetry) return Future.value();
    final settled = Completer<void>();
    _pending = settled.future;
    failure = null;
    notifyListeners();
    unawaited(
      _attempt(settled, selectLegacyDirectory, importSource, startFresh),
    );
    return settled.future;
  }

  Future<void> _teardown() async {
    final library = _library;
    if (library != null) {
      await library.database.close();
      _library = null;
    }
  }

  Future<void> _attempt(
    Completer<void> settled,
    bool selectLegacyDirectory,
    File? importSource,
    bool startFresh,
  ) async {
    try {
      // A failed close is not permission to start another opener. Retain the
      // handle and try teardown again before any subsequent storage attempt.
      await _teardown();
      if (_closed) return;
      _library = await open(
        selectLegacyDirectory: selectLegacyDirectory,
        importSource: importSource,
        startFresh: startFresh,
      );
      if (_closed) return;
      // Also enforce readiness for lazy/injected openers at this boundary.
      await database.select(database.algorithms).get();
      if (_closed) return;
      _activationStarted = true;
      for (final activate in activationSteps) {
        if (_closed) return;
        await activate(database);
      }
      if (!_closed) {
        _ready = true;
        StartupLogService.log(
          'Library ready: location=${location ?? 'default'}',
        );
      }
    } catch (error, stackTrace) {
      failure = error;
      StartupLogService.logError('Library startup failed', error, stackTrace);
    } finally {
      if (!ready) {
        try {
          await _teardown();
        } catch (error) {
          failure = error;
        }
      }
      _pending = null;
      settled.complete();
      notifyListeners();
    }
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _ready = false;
    notifyListeners();
    return _closing = _finishClose();
  }

  Future<void> _finishClose() async {
    await _pending;
    await _teardown();
  }
}
