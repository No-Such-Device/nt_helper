import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/models/package_analysis.dart';
import 'package:nt_helper/models/package_file.dart';
import 'package:nt_helper/ui/widgets/package_install_dialog.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

void main() {
  late MockDistingCubit mockDistingCubit;

  setUp(() {
    mockDistingCubit = MockDistingCubit();
  });

  // Helper function to create test package analysis
  PackageAnalysis createTestAnalysis({
    int fileCount = 3,
    int conflictCount = 1,
    List<PackageFile>? customFiles,
  }) {
    final files =
        customFiles ??
        List.generate(
          fileCount,
          (i) => PackageFile(
            relativePath: 'path$i/file$i.json',
            targetPath: '/presets/path$i/file$i.json',
            size: 1024 * (i + 1),
            hasConflict: i < conflictCount,
            action: FileAction.install,
          ),
        );

    return PackageAnalysis(
      packageName: 'test_package.zip',
      presetName: 'Test Package',
      author: 'Test Author',
      version: '1.0.0',
      files: files,
      manifest: const {
        'preset_name': 'Test Package',
        'author': 'Test Author',
        'version': '1.0.0',
      },
      isValid: true,
    );
  }

  // Helper to create test widget
  Widget createTestWidget({
    required PackageAnalysis analysis,
    Uint8List? packageData,
    VoidCallback? onInstall,
    VoidCallback? onCancel,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PackageInstallDialog(
          analysis: analysis,
          packageData: packageData ?? Uint8List(0),
          distingCubit: mockDistingCubit,
          onInstall: onInstall,
          onCancel: onCancel,
        ),
      ),
    );
  }

  group('PackageInstallDialog - UI Display', () {
    testWidgets('displays package information', (tester) async {
      final analysis = createTestAnalysis();

      await tester.pumpWidget(createTestWidget(analysis: analysis));

      expect(find.text('Install Package: Test Package'), findsOneWidget);
      expect(find.text('by Test Author'), findsOneWidget);
      expect(find.text('Version 1.0.0'), findsOneWidget);
      expect(find.text('3 files'), findsOneWidget);
      expect(find.text('1 conflicts'), findsOneWidget);
    });

    testWidgets('displays file list with correct structure', (tester) async {
      final analysis = createTestAnalysis(fileCount: 3);

      await tester.pumpWidget(createTestWidget(analysis: analysis));

      // Should display expansion tiles for directories
      expect(find.byType(ExpansionTile), findsWidgets);

      // Should display list tiles for files
      expect(find.byType(ListTile), findsWidgets);
    });

    testWidgets('shows install button with file count', (tester) async {
      final analysis = createTestAnalysis(fileCount: 5);

      await tester.pumpWidget(createTestWidget(analysis: analysis));

      expect(
        find.widgetWithText(ElevatedButton, 'Install 5 Files'),
        findsOneWidget,
      );
    });

    testWidgets('shows cancel button', (tester) async {
      final analysis = createTestAnalysis();

      await tester.pumpWidget(createTestWidget(analysis: analysis));

      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('displays conflict resolution buttons when conflicts exist', (
      tester,
    ) async {
      final analysis = createTestAnalysis(conflictCount: 2);

      await tester.pumpWidget(createTestWidget(analysis: analysis));

      expect(find.text('Install All'), findsOneWidget);
      expect(find.text('Skip Conflicts'), findsOneWidget);
      expect(find.text('Skip All'), findsOneWidget);
    });

    testWidgets('hides conflict resolution buttons when no conflicts', (
      tester,
    ) async {
      final analysis = createTestAnalysis(conflictCount: 0);

      await tester.pumpWidget(createTestWidget(analysis: analysis));

      expect(find.text('Install All'), findsNothing);
      expect(find.text('Skip Conflicts'), findsNothing);
      expect(find.text('Skip All'), findsNothing);
    });
  });

  group('PackageInstallDialog - Button States', () {
    testWidgets('install button is enabled when files selected for install', (
      tester,
    ) async {
      final analysis = createTestAnalysis();

      await tester.pumpWidget(createTestWidget(analysis: analysis));

      final installButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Install 3 Files'),
      );

      expect(installButton.onPressed, isNotNull);
    });

    testWidgets('install button is disabled when no files selected', (
      tester,
    ) async {
      final files = [
        PackageFile(
          relativePath: 'file.json',
          targetPath: '/presets/file.json',
          size: 1024,
          hasConflict: false,
          action: FileAction.skip,
        ),
      ];
      final analysis = createTestAnalysis(customFiles: files);

      await tester.pumpWidget(createTestWidget(analysis: analysis));

      final installButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Install 0 Files'),
      );

      expect(installButton.onPressed, isNull);
    });

    testWidgets('cancel button calls onCancel callback', (tester) async {
      bool cancelCalled = false;
      final analysis = createTestAnalysis();

      await tester.pumpWidget(
        createTestWidget(
          analysis: analysis,
          onCancel: () => cancelCalled = true,
        ),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(cancelCalled, isTrue);
    });
  });

  group('PackageInstallDialog - Installation Flow', () {
    testWidgets('shows progress indicator during installation', (tester) async {
      final analysis = createTestAnalysis();

      final installation = Completer<void>();
      // Keep installation pending until loading assertions finish.
      when(
        () => mockDistingCubit.installPackageFiles(
          any(),
          any(),
          onFileStart: any(named: 'onFileStart'),
          onFileProgress: any(named: 'onFileProgress'),
          onFileComplete: any(named: 'onFileComplete'),
          onFileError: any(named: 'onFileError'),
        ),
      ).thenAnswer((invocation) async {
        final onFileStart =
            invocation.namedArguments[const Symbol('onFileStart')]
                as Function(String, int, int)?;
        if (onFileStart != null) {
          onFileStart('file1.json', 1, 3);
        }
        await installation.future;
      });

      await tester.pumpWidget(createTestWidget(analysis: analysis));

      // Tap install button
      await tester.tap(find.widgetWithText(ElevatedButton, 'Install 3 Files'));
      await tester.pump();

      // Progress indicator should be visible
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Installing: file1.json (0/3)'), findsOneWidget);

      installation.complete();
      // Wait for installation to complete
      await tester.pumpAndSettle();
    });

    testWidgets('disables buttons during installation', (tester) async {
      final analysis = createTestAnalysis();

      final installation = Completer<void>();
      // Keep installation pending until loading assertions finish.
      when(
        () => mockDistingCubit.installPackageFiles(
          any(),
          any(),
          onFileStart: any(named: 'onFileStart'),
          onFileProgress: any(named: 'onFileProgress'),
          onFileComplete: any(named: 'onFileComplete'),
          onFileError: any(named: 'onFileError'),
        ),
      ).thenAnswer((invocation) async {
        await installation.future;
      });

      await tester.pumpWidget(createTestWidget(analysis: analysis));

      // Tap install button
      await tester.tap(find.widgetWithText(ElevatedButton, 'Install 3 Files'));
      await tester.pump();

      // Both buttons should be disabled during installation
      final installButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Install 3 Files'),
      );
      final cancelButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancel'),
      );

      expect(installButton.onPressed, isNull);
      expect(cancelButton.onPressed, isNull);
      installation.complete();

      await tester.pumpAndSettle();
    });

    testWidgets('calls installPackageFiles with correct parameters', (
      tester,
    ) async {
      final analysis = createTestAnalysis();
      final packageData = Uint8List.fromList([1, 2, 3, 4]);

      when(
        () => mockDistingCubit.installPackageFiles(
          any(),
          any(),
          onFileStart: any(named: 'onFileStart'),
          onFileProgress: any(named: 'onFileProgress'),
          onFileComplete: any(named: 'onFileComplete'),
          onFileError: any(named: 'onFileError'),
        ),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(
        createTestWidget(analysis: analysis, packageData: packageData),
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Install 3 Files'));
      await tester.pumpAndSettle();

      verify(
        () => mockDistingCubit.installPackageFiles(
          analysis.files,
          any(),
          onFileStart: any(named: 'onFileStart'),
          onFileProgress: any(named: 'onFileProgress'),
          onFileComplete: any(named: 'onFileComplete'),
          onFileError: any(named: 'onFileError'),
        ),
      ).called(1);
    });

    testWidgets('updates progress during installation', (tester) async {
      final analysis = createTestAnalysis();
      final firstFile = Completer<void>();
      final secondFile = Completer<void>();

      when(
        () => mockDistingCubit.installPackageFiles(
          any(),
          any(),
          onFileStart: any(named: 'onFileStart'),
          onFileProgress: any(named: 'onFileProgress'),
          onFileComplete: any(named: 'onFileComplete'),
          onFileError: any(named: 'onFileError'),
        ),
      ).thenAnswer((invocation) async {
        final onFileStart =
            invocation.namedArguments[const Symbol('onFileStart')]
                as Function(String, int, int)?;
        final onFileComplete =
            invocation.namedArguments[const Symbol('onFileComplete')]
                as Function(String)?;

        // Simulate file-by-file installation
        if (onFileStart != null) {
          onFileStart('file1.json', 1, 3);
        }
        await firstFile.future;
        if (onFileComplete != null) {
          onFileComplete('file1.json');
        }

        if (onFileStart != null) {
          onFileStart('file2.json', 2, 3);
        }
        await secondFile.future;
        if (onFileComplete != null) {
          onFileComplete('file2.json');
        }
      });

      await tester.pumpWidget(createTestWidget(analysis: analysis));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Install 3 Files'));
      await tester.pump();

      // Check initial progress
      expect(find.text('Installing: file1.json (0/3)'), findsOneWidget);

      firstFile.complete();
      await tester.pump();

      // Progress should update
      expect(find.text('Installing: file2.json (1/3)'), findsOneWidget);
      secondFile.complete();

      await tester.pumpAndSettle();
    });

    testWidgets('calls onInstall callback after successful installation', (
      tester,
    ) async {
      bool installCalled = false;
      final analysis = createTestAnalysis();

      when(
        () => mockDistingCubit.installPackageFiles(
          any(),
          any(),
          onFileStart: any(named: 'onFileStart'),
          onFileProgress: any(named: 'onFileProgress'),
          onFileComplete: any(named: 'onFileComplete'),
          onFileError: any(named: 'onFileError'),
        ),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(
        createTestWidget(
          analysis: analysis,
          onInstall: () => installCalled = true,
        ),
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Install 3 Files'));
      await tester.pumpAndSettle();

      expect(installCalled, isTrue);
    });
  });

  group('PackageInstallDialog - Error Handling', () {
    testWidgets('shows error dialog when installation fails', (tester) async {
      final analysis = createTestAnalysis();

      when(
        () => mockDistingCubit.installPackageFiles(
          any(),
          any(),
          onFileStart: any(named: 'onFileStart'),
          onFileProgress: any(named: 'onFileProgress'),
          onFileComplete: any(named: 'onFileComplete'),
          onFileError: any(named: 'onFileError'),
        ),
      ).thenAnswer((invocation) async {
        final onFileError =
            invocation.namedArguments[const Symbol('onFileError')]
                as Function(String, String)?;
        if (onFileError != null) {
          onFileError('file1.json', 'Write failed');
        }
      });

      await tester.pumpWidget(createTestWidget(analysis: analysis));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Install 3 Files'));
      await tester.pumpAndSettle();

      // Error dialog should be shown
      expect(find.text('Installation Errors'), findsOneWidget);
      expect(find.textContaining('file1.json: Write failed'), findsOneWidget);
    });

    testWidgets('error dialog shows partial success count', (tester) async {
      final analysis = createTestAnalysis(fileCount: 3);

      when(
        () => mockDistingCubit.installPackageFiles(
          any(),
          any(),
          onFileStart: any(named: 'onFileStart'),
          onFileProgress: any(named: 'onFileProgress'),
          onFileComplete: any(named: 'onFileComplete'),
          onFileError: any(named: 'onFileError'),
        ),
      ).thenAnswer((invocation) async {
        final onFileStart =
            invocation.namedArguments[const Symbol('onFileStart')]
                as Function(String, int, int)?;
        final onFileComplete =
            invocation.namedArguments[const Symbol('onFileComplete')]
                as Function(String)?;
        final onFileError =
            invocation.namedArguments[const Symbol('onFileError')]
                as Function(String, String)?;

        // First file succeeds
        if (onFileStart != null) {
          onFileStart('file1.json', 1, 3);
        }
        if (onFileComplete != null) {
          onFileComplete('file1.json');
        }

        // Second file fails
        if (onFileStart != null) {
          onFileStart('file2.json', 2, 3);
        }
        if (onFileError != null) {
          onFileError('file2.json', 'Write failed');
        }
      });

      await tester.pumpWidget(createTestWidget(analysis: analysis));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Install 3 Files'));
      await tester.pumpAndSettle();

      // Should show partial success in error dialog
      expect(
        find.textContaining('Successfully installed: 1 of 3 files'),
        findsOneWidget,
      );
    });

    testWidgets('error dialog has close button', (tester) async {
      final analysis = createTestAnalysis();

      when(
        () => mockDistingCubit.installPackageFiles(
          any(),
          any(),
          onFileStart: any(named: 'onFileStart'),
          onFileProgress: any(named: 'onFileProgress'),
          onFileComplete: any(named: 'onFileComplete'),
          onFileError: any(named: 'onFileError'),
        ),
      ).thenAnswer((invocation) async {
        final onFileError =
            invocation.namedArguments[const Symbol('onFileError')]
                as Function(String, String)?;
        if (onFileError != null) {
          onFileError('file1.json', 'Write failed');
        }
      });

      await tester.pumpWidget(createTestWidget(analysis: analysis));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Install 3 Files'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextButton, 'Close'), findsOneWidget);
    });

    testWidgets('does not call onInstall when errors occur', (tester) async {
      bool installCalled = false;
      final analysis = createTestAnalysis();

      when(
        () => mockDistingCubit.installPackageFiles(
          any(),
          any(),
          onFileStart: any(named: 'onFileStart'),
          onFileProgress: any(named: 'onFileProgress'),
          onFileComplete: any(named: 'onFileComplete'),
          onFileError: any(named: 'onFileError'),
        ),
      ).thenAnswer((invocation) async {
        final onFileError =
            invocation.namedArguments[const Symbol('onFileError')]
                as Function(String, String)?;
        if (onFileError != null) {
          onFileError('file1.json', 'Write failed');
        }
      });

      await tester.pumpWidget(
        createTestWidget(
          analysis: analysis,
          onInstall: () => installCalled = true,
        ),
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Install 3 Files'));
      await tester.pumpAndSettle();

      expect(installCalled, isFalse);
    });
  });

  group('PackageInstallDialog - File Action Management', () {
    testWidgets('bulk action "Install All" sets all files to install', (
      tester,
    ) async {
      final files = [
        PackageFile(
          relativePath: 'file1.json',
          targetPath: '/presets/file1.json',
          size: 1024,
          hasConflict: true,
          action: FileAction.skip,
        ),
        PackageFile(
          relativePath: 'file2.json',
          targetPath: '/presets/file2.json',
          size: 1024,
          hasConflict: true,
          action: FileAction.skip,
        ),
      ];
      final analysis = createTestAnalysis(customFiles: files);

      await tester.pumpWidget(createTestWidget(analysis: analysis));

      // Initially should show 0 files to install
      expect(
        find.widgetWithText(ElevatedButton, 'Install 0 Files'),
        findsOneWidget,
      );

      // Tap "Install All" button
      await tester.tap(find.widgetWithText(ActionChip, 'Install All'));
      await tester.pumpAndSettle();

      // Should now show 2 files to install
      expect(
        find.widgetWithText(ElevatedButton, 'Install 2 Files'),
        findsOneWidget,
      );
    });

    testWidgets('bulk action "Skip All" sets all files to skip', (
      tester,
    ) async {
      final analysis = createTestAnalysis(fileCount: 3, conflictCount: 1);

      await tester.pumpWidget(createTestWidget(analysis: analysis));

      // Initially should show 3 files to install
      expect(
        find.widgetWithText(ElevatedButton, 'Install 3 Files'),
        findsOneWidget,
      );

      // Tap "Skip All" button
      await tester.tap(find.widgetWithText(ActionChip, 'Skip All'));
      await tester.pumpAndSettle();

      // Should now show button is disabled (0 files)
      final installButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Install 0 Files'),
      );
      expect(installButton.onPressed, isNull);
    });

    testWidgets('bulk action "Skip Conflicts" skips only conflict files', (
      tester,
    ) async {
      final files = [
        PackageFile(
          relativePath: 'conflict.json',
          targetPath: '/presets/conflict.json',
          size: 1024,
          hasConflict: true,
          action: FileAction.install,
        ),
        PackageFile(
          relativePath: 'new.json',
          targetPath: '/presets/new.json',
          size: 1024,
          hasConflict: false,
          action: FileAction.install,
        ),
      ];
      final analysis = createTestAnalysis(customFiles: files);

      await tester.pumpWidget(createTestWidget(analysis: analysis));

      // Initially should show 2 files to install
      expect(
        find.widgetWithText(ElevatedButton, 'Install 2 Files'),
        findsOneWidget,
      );

      // Tap "Skip Conflicts" button
      await tester.tap(find.widgetWithText(ActionChip, 'Skip Conflicts'));
      await tester.pumpAndSettle();

      // Should now show button with 1 file to install (the non-conflict file)
      // Use textContaining to handle singular/plural variations
      expect(find.textContaining('Install 1'), findsOneWidget);
    });
  });
}
