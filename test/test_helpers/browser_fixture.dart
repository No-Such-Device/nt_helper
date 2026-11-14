import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:nt_helper/cubit/preset_browser_state.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:nt_helper/ui/widgets/preset_browser_dialog.dart';

/// Static cascade renderer fixture; production owns one root-to-leaf stack.
PresetBrowserState browserFixture({
  required String currentPath,
  required List<DirectoryEntry> leftPanelItems,
  required List<DirectoryEntry> centerPanelItems,
  required List<DirectoryEntry> rightPanelItems,
  DirectoryEntry? selectedLeftItem,
  DirectoryEntry? selectedCenterItem,
  DirectoryEntry? selectedRightItem,
  List<String> navigationHistory = const [],
  required bool sortByDate,
  String? drillPath,
  List<DirectoryEntry>? currentDrillItems,
  DirectoryEntry? selectedDrillItem,
}) {
  String clean(String name) => name.replaceFirst(RegExp(r'/$'), '');
  String join(String base, String child) =>
      '${base == '/' ? '' : base}/${clean(child)}';
  final left = drillPath ?? currentPath;
  final paths = <String>['/'];
  final parts = left.split('/').where((s) => s.isNotEmpty).toList();
  for (var i = 1; i <= parts.length; i++) {
    paths.add('/${parts.take(i).join('/')}');
  }
  final stack = <BrowserFrame>[
    for (var i = 0; i < paths.length; i++)
      BrowserFrame(
        path: paths[i],
        selectedName: i + 1 < paths.length
            ? '${parts[i]}/'
            : (selectedDrillItem ?? selectedLeftItem)?.name,
      ),
  ];
  final listings = <String, List<DirectoryEntry>>{
    left: currentDrillItems ?? leftPanelItems,
  };
  if (drillPath == null && selectedLeftItem?.isDirectory == true) {
    final center = join(left, selectedLeftItem!.name);
    stack.add(
      BrowserFrame(path: center, selectedName: selectedCenterItem?.name),
    );
    listings[center] = centerPanelItems;
    if (selectedCenterItem?.isDirectory == true) {
      final right = join(center, selectedCenterItem!.name);
      stack.add(
        BrowserFrame(path: right, selectedName: selectedRightItem?.name),
      );
      listings[right] = rightPanelItems;
    }
  }
  return PresetBrowserState.loaded(
    browser: BrowserSnapshot(
      stack: stack,
      sortByDate: sortByDate,
      listings: listings,
    ),
  );
}

Widget testThreePanelNavigator({
  required List<DirectoryEntry> leftPanelItems,
  required List<DirectoryEntry> centerPanelItems,
  required List<DirectoryEntry> rightPanelItems,
  DirectoryEntry? selectedLeftItem,
  DirectoryEntry? selectedCenterItem,
  DirectoryEntry? selectedRightItem,
  required String currentPath,
  required void Function(DirectoryEntry, PanelPosition) onItemSelected,
  void Function(List<XFile>, String)? onFilesDropped,
}) => ThreePanelNavigator(
  browser: browserFixture(
    currentPath: currentPath,
    leftPanelItems: leftPanelItems,
    centerPanelItems: centerPanelItems,
    rightPanelItems: rightPanelItems,
    selectedLeftItem: selectedLeftItem,
    selectedCenterItem: selectedCenterItem,
    selectedRightItem: selectedRightItem,
    sortByDate: false,
  ).view!,
  onItemSelected: onItemSelected,
  onFilesDropped: onFilesDropped,
);
