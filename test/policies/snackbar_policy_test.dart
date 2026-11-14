import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

// Dynamic exceptional helpers are exercised by their widget tests (notably
// plugin cleanup). This app-wide guard also catches affirmative literals in
// nested Text widgets and helper callers, beyond the browser-only regressions.
class _SnackbarMessages extends RecursiveAstVisitor<void> {
  final List<String> violations = [];
  static final affirmative = RegExp(
    r'^(Uploaded|Downloaded|Created|Renamed|Deleted|Removed|Assigned|Copied|Connected|Disconnected|Restored)\b|'
    r'^(Checkpoint created|Reboot command sent|SD card remount requested|Rescanning|Refreshing algorithm|Loading plugin)|'
    r'copied (to clipboard|\(data URL\))|^Routing .* shared$',
    caseSensitive: false,
  );

  void inspect(AstNode node) {
    final strings = _Strings();
    node.accept(strings);
    violations.addAll(strings.values.where(affirmative.hasMatch));
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'SnackBar') inspect(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == '_showException' ||
        node.methodName.name == '_showFeedback') {
      inspect(node.argumentList);
    }
    super.visitMethodInvocation(node);
  }
}

class _Strings extends RecursiveAstVisitor<void> {
  final List<String> values = [];
  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    values.add(node.value);
  }

  @override
  void visitInterpolationString(InterpolationString node) {
    values.add(node.value);
  }
}

void main() {
  test(
    'app-wide snackbar producers and feedback callers contain no routine success or progress messages',
    () {
      final violations = <String>[];
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();
        if (!source.contains('SnackBar') &&
            !source.contains('_showException')) {
          continue;
        }
        final visitor = _SnackbarMessages();
        parseString(content: source, path: file.path).unit.accept(visitor);
        violations.addAll(
          visitor.violations.map((message) => '${file.path}: $message'),
        );
      }
      expect(
        violations,
        isEmpty,
        reason:
            'AGENTS.md reserves snackbars for errors and exceptional warnings.',
      );
    },
  );
}
