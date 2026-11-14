import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:nt_helper/cubit/preset_browser_state.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:nt_helper/ui/widgets/preset_browser_dialog.dart';

/// Converts existing static renderer fixtures to independent pane locations.
/// Production has no legacy cascading-column or mobile-state adapter.
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
  final center = selectedLeftItem?.isDirectory == true
      ? join(currentPath, selectedLeftItem!.name)
      : '/empty-center';
  final right = selectedCenterItem?.isDirectory == true
      ? join(center, selectedCenterItem!.name)
      : '/empty-right';
  return PresetBrowserState.loaded(
    browser: BrowserSnapshot(
      panes: [
        BrowserPane(
          stack: [
            for (final path in navigationHistory) BrowserFrame(path: path),
            BrowserFrame(
              path: left,
              selectedName: (selectedDrillItem ?? selectedLeftItem)?.name,
            ),
          ],
        ),
        BrowserPane(
          stack: [
            BrowserFrame(path: center, selectedName: selectedCenterItem?.name),
          ],
        ),
        BrowserPane(
          stack: [
            BrowserFrame(path: right, selectedName: selectedRightItem?.name),
          ],
        ),
      ],
      sortByDate: sortByDate,
      listings: {
        left: currentDrillItems ?? leftPanelItems,
        center: centerPanelItems,
        right: rightPanelItems,
      },
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
