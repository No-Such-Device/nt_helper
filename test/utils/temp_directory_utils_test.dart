import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nt_helper/utils/temp_directory_utils.dart';

void main() {
  group('TempDirectoryUtils', () {
    group('getWritableTempDirectory', () {
      test('returns primary when it is writable', () async {
        final dir = await TempDirectoryUtils.getWritableTempDirectory(
          primaryProvider: () async => Directory.systemTemp,
        );
        expect(dir.path, Directory.systemTemp.path);
      });

      test('falls back when primary returns non-existent directory', () async {
        final dir = await TempDirectoryUtils.getWritableTempDirectory(
          primaryProvider: () async => Directory('/nonexistent/path'),
          fallbackProvider: () => Directory.systemTemp,
        );
        expect(dir.path, Directory.systemTemp.path);
      });

      test('falls back when primary throws FileSystemException', () async {
        final dir = await TempDirectoryUtils.getWritableTempDirectory(
          primaryProvider: () async =>
              throw const FileSystemException('no temp dir'),
          fallbackProvider: () => Directory.systemTemp,
        );
        expect(dir.path, Directory.systemTemp.path);
      });

      test(
        'falls back when primary throws MissingPlatformDirectoryException',
        () async {
          final dir = await TempDirectoryUtils.getWritableTempDirectory(
            primaryProvider: () async =>
                throw MissingPlatformDirectoryException('no temp dir'),
            fallbackProvider: () => Directory.systemTemp,
          );
          expect(dir.path, Directory.systemTemp.path);
        },
      );

      test('falls back when primary throws generic exception', () async {
        final dir = await TempDirectoryUtils.getWritableTempDirectory(
          primaryProvider: () async => throw Exception('unexpected'),
          fallbackProvider: () => Directory.systemTemp,
        );
        expect(dir.path, Directory.systemTemp.path);
      });

      test('throws FileSystemException when both fail', () async {
        expect(
          () => TempDirectoryUtils.getWritableTempDirectory(
            primaryProvider: () async => Directory('/nonexistent/primary'),
            fallbackProvider: () => Directory('/nonexistent/fallback'),
          ),
          throwsA(isA<FileSystemException>()),
        );
      });
    });

    group('isWritable', () {
      test('returns true for writable directory', () async {
        final result = await TempDirectoryUtils.isWritable(
          Directory.systemTemp,
        );
        expect(result, isTrue);
      });

      test('returns false for non-existent directory', () async {
        final result = await TempDirectoryUtils.isWritable(
          Directory('/nonexistent/path'),
        );
        expect(result, isFalse);
      });

      
    });
  });
}
