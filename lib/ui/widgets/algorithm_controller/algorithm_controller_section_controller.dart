import 'dart:async';

import 'package:material_ui/material_ui.dart';

typedef AlgorithmControllerSectionReference = ({String path, String title});

/// Owns the expansion controllers for one algorithm controller document.
///
/// The owner should live above transient parameter/routing layouts so section
/// state survives when the Lua view is rebuilt.
class AlgorithmControllerSectionController extends ChangeNotifier {
  AlgorithmControllerSectionController({required bool initiallyCollapsed})
    : _sectionsCollapsed = initiallyCollapsed;

  final Map<String, ExpansibleController> _controllers = {};
  final Set<ExpansibleController> _retiredControllers = {};
  List<AlgorithmControllerSectionReference> _sections = const [];
  bool _sectionsCollapsed;
  bool _updatingControllers = false;
  bool _deferredNotificationScheduled = false;
  bool _disposed = false;

  bool get sectionsCollapsed => _sectionsCollapsed;

  void synchronizeSections(List<AlgorithmControllerSectionReference> sections) {
    _sections = List.unmodifiable(sections);
    final activePaths = sections.map((section) => section.path).toSet();
    final removedPaths = _controllers.keys
        .where((path) => !activePaths.contains(path))
        .toList();
    for (final path in removedPaths) {
      final controller = _controllers.remove(path);
      if (controller != null) _retireController(controller);
    }
    for (final section in sections) {
      _controllers.putIfAbsent(section.path, () {
        final controller = ExpansibleController();
        if (!_sectionsCollapsed) controller.expand();
        controller.addListener(_handleControllerChanged);
        return controller;
      });
    }
    _updateCollapsedState(deferNotification: true);
  }

  ExpansibleController controllerFor(String path) {
    return _controllers[path] ??
        (throw StateError('No algorithm controller section at $path'));
  }

  /// Expands the requested section and its ancestors, and collapses its peers.
  ///
  /// Returns the selected section title, or `null` when [sectionIndex] is not
  /// present in the current document.
  String? showOnlySection(int sectionIndex) {
    if (sectionIndex < 0 || sectionIndex >= _sections.length) return null;

    final selected = _sections[sectionIndex];
    _mutateControllers(() {
      for (final section in _sections) {
        final shouldExpand =
            section.path == selected.path ||
            selected.path.startsWith('${section.path}/');
        final controller = controllerFor(section.path);
        if (shouldExpand) {
          controller.expand();
        } else {
          controller.collapse();
        }
      }
    });
    return selected.title;
  }

  void toggleAll() {
    final collapse = !_sectionsCollapsed;
    _mutateControllers(() {
      for (final section in _sections) {
        final controller = controllerFor(section.path);
        if (collapse) {
          controller.collapse();
        } else {
          controller.expand();
        }
      }
      if (_sections.isEmpty) {
        _setSectionsCollapsed(collapse);
      }
    });
  }

  void _mutateControllers(VoidCallback update) {
    _updatingControllers = true;
    try {
      update();
    } finally {
      _updatingControllers = false;
      _updateCollapsedState();
    }
  }

  void _handleControllerChanged() {
    if (!_updatingControllers) _updateCollapsedState();
  }

  void _updateCollapsedState({bool deferNotification = false}) {
    if (_sections.isEmpty) return;
    _setSectionsCollapsed(
      _sections.every((section) => !controllerFor(section.path).isExpanded),
      deferNotification: deferNotification,
    );
  }

  void _setSectionsCollapsed(bool collapsed, {bool deferNotification = false}) {
    if (_sectionsCollapsed == collapsed) return;
    _sectionsCollapsed = collapsed;
    if (!deferNotification) {
      notifyListeners();
      return;
    }
    if (_deferredNotificationScheduled) return;
    _deferredNotificationScheduled = true;
    unawaited(
      WidgetsBinding.instance.endOfFrame.then((_) {
        _deferredNotificationScheduled = false;
        if (!_disposed) notifyListeners();
      }),
    );
  }

  void _retireController(ExpansibleController controller) {
    controller.removeListener(_handleControllerChanged);
    _retiredControllers.add(controller);
    unawaited(
      WidgetsBinding.instance.endOfFrame.then((_) {
        if (_retiredControllers.remove(controller)) controller.dispose();
      }),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    for (final controller in _controllers.values) {
      controller
        ..removeListener(_handleControllerChanged)
        ..dispose();
    }
    _controllers.clear();
    for (final controller in _retiredControllers) {
      controller.dispose();
    }
    _retiredControllers.clear();
    _sections = const [];
    super.dispose();
  }
}
