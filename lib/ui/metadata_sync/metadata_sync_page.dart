import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/domain/offline_disting_midi_manager.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart'
    show IDistingMidiManager;
import 'package:nt_helper/domain/disting_nt_sysex.dart' show AlgorithmInfo;
import 'package:nt_helper/ui/metadata_sync/metadata_sync_cubit.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/services/metadata_sync_service.dart';
import 'package:nt_helper/ui/widgets/algorithm_export_dialog.dart';
import 'package:nt_helper/ui/widgets/debug_metadata_export_dialog.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';
import 'package:nt_helper/ui/widgets/template_preview_dialog.dart';
import 'package:nt_helper/ui/template_manager/current_preset_template_source.dart';
import 'package:nt_helper/ui/template_manager/template_manager_screen.dart';

class MetadataSyncAnnouncementListener extends StatelessWidget {
  final Widget child;
  final MetadataSyncCubit? bloc;

  const MetadataSyncAnnouncementListener({
    super.key,
    required this.child,
    this.bloc,
  });

  @override
  Widget build(BuildContext context) {
    return BlocListener<MetadataSyncCubit, MetadataSyncState>(
      bloc: bloc,
      listener: (context, metaState) {
        if (metaState is SyncingMetadata) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            metaState.mainMessage,
            TextDirection.ltr,
          );
        } else if (metaState is MetadataSyncSuccess) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Metadata sync complete',
            TextDirection.ltr,
          );
        } else if (metaState is MetadataSyncFailure) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Metadata sync failed: ${metaState.error}',
            TextDirection.ltr,
          );
        } else if (metaState is PresetSaveSuccess) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Preset saved',
            TextDirection.ltr,
          );
        } else if (metaState is PresetDeleteSuccess) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Preset deleted',
            TextDirection.ltr,
          );
        }
      },
      child: child,
    );
  }
}

class MetadataSyncPage extends StatelessWidget {
  // Accept DistingCubit as a parameter
  final DistingCubit distingCubit;

  const MetadataSyncPage({super.key, required this.distingCubit});

  @override
  Widget build(BuildContext context) {
    // Get AppDatabase from context (RepositoryProvider)
    final database = context.read<AppDatabase>();
    // Get manager instance (if any) from DistingCubit state later
    // final distingManager = distingCubit.disting(); // No longer needed here
    // final bool isConnected = distingManager != null; // Determined by DistingState

    // Provide MetadataSyncCubit with DistingCubit for CPU monitoring control
    return BlocProvider(
      create: (context) =>
          MetadataSyncCubit(database, distingCubit)..loadLocalData(),
      child: BlocBuilder<DistingCubit, DistingState>(
        // Rebuild the whole page based on DistingState (online/offline)
        bloc: distingCubit,
        builder: (context, distingState) {
          // Determine online/offline/connected status from DistingState
          final bool isOffline = switch (distingState) {
            DistingStateSynchronized(offline: final o) => o,
            _ => false,
          };
          final bool isConnected = switch (distingState) {
            DistingStateSynchronized(offline: final o) => !o,
            DistingStateConnected() => true,
            _ => false,
          };

          // Handle disconnected/invalid states by navigating back
          if (distingState is DistingStateInitial ||
              distingState is DistingStateSelectDevice) {
            // Connection was lost or device disconnected - navigate back to main screen
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            });
            return const Center(child: CircularProgressIndicator());
          }

          // Get the current manager if available (online or offline)
          final currentManager = distingCubit.disting();

          // Provide the DistingCubit down the tree using BlocProvider.value
          return BlocProvider.value(
            value: distingCubit,
            child: BlocBuilder<MetadataSyncCubit, MetadataSyncState>(
              builder: (context, metaState) {
                return PopScope(
                  canPop:
                      !(metaState is SyncingMetadata ||
                          metaState is SavingPreset ||
                          metaState is DeletingPreset),
                  onPopInvokedWithResult: (didPop, result) {
                    if (!didPop) {
                      // Cancel sync if in progress
                      context.read<MetadataSyncCubit>().cancelMetadataSync();
                    }
                  },
                  child: Scaffold(
                    appBar: AppBar(
                      title: Text('Offline Data'),
                      leading:
                          BlocBuilder<MetadataSyncCubit, MetadataSyncState>(
                            builder: (context, metaState) {
                              return BackButton(
                                onPressed: () {
                                  // Cancel sync if in progress, otherwise just navigate back
                                  if (metaState is SyncingMetadata ||
                                      metaState is SavingPreset ||
                                      metaState is DeletingPreset) {
                                    context
                                        .read<MetadataSyncCubit>()
                                        .cancelMetadataSync();
                                  } else {
                                    Navigator.maybePop(context);
                                  }
                                },
                              );
                            },
                          ),
                      actions: [
                        // --- Offline Mode Toggle --- (Interacts with DistingCubit)
                        BlocBuilder<MetadataSyncCubit, MetadataSyncState>(
                          // Still watch MetadataSyncCubit for busy state
                          builder: (metaCtx, metaState) {
                            // Busy state checks (simplified, check both cubits)
                            final isMetaBusy =
                                metaState is! ViewingLocalData &&
                                metaState is! Idle &&
                                metaState is! Failure;
                            final isDistingBusy = switch (distingState) {
                              DistingStateSynchronized(loading: final l) => l,
                              _ => false,
                            };
                            final isBusy = isMetaBusy || isDistingBusy;

                            return IconButton(
                              icon: Icon(
                                isOffline ? Icons.wifi_off : Icons.wifi,
                                semanticLabel: isOffline
                                    ? 'Go Online'
                                    : 'Work Offline',
                              ),
                              tooltip: isOffline ? 'Go Online' : 'Work Offline',
                              onPressed: isBusy
                                  ? null
                                  : () {
                                      if (isOffline) {
                                        // Use the distingCubit variable directly
                                        distingCubit.goOnline();
                                      } else {
                                        // Use the distingCubit variable directly
                                        distingCubit.goOffline();
                                      }
                                    },
                            );
                          },
                        ),
                        // --- Sync Metadata Button --- (Uses MetadataSyncCubit)
                        BlocBuilder<MetadataSyncCubit, MetadataSyncState>(
                          builder: (metaCtx, metaState) {
                            final isMetaBusy =
                                metaState is! ViewingLocalData &&
                                metaState is! Idle &&
                                metaState is! Failure;
                            final isDistingBusy = switch (distingState) {
                              DistingStateSynchronized(loading: final l) => l,
                              _ => false,
                            };
                            final isBusy = isMetaBusy || isDistingBusy;
                            // Can sync if connected and not busy
                            final canSync = isConnected && !isBusy;
                            return IconButton(
                              icon: const Icon(
                                Icons.sync,
                                semanticLabel: 'Sync From Device',
                              ),
                              tooltip: 'Sync From Device',
                              // Pass manager only if action is possible
                              onPressed: canSync && currentManager != null
                                  ? () => _showSyncConfirmationDialog(
                                      metaCtx,
                                      currentManager,
                                    )
                                  : null,
                            );
                          },
                        ),
                        // --- Save Preset Button --- (Uses MetadataSyncCubit)
                        BlocBuilder<MetadataSyncCubit, MetadataSyncState>(
                          builder: (metaCtx, metaState) {
                            final isMetaBusy =
                                metaState is! ViewingLocalData &&
                                metaState is! Idle &&
                                metaState is! Failure;
                            final isDistingBusy = switch (distingState) {
                              DistingStateSynchronized(loading: final l) => l,
                              _ => false,
                            };
                            final isBusy = isMetaBusy || isDistingBusy;
                            // Can save if connected and not busy
                            final canSave = isConnected && !isBusy;
                            return IconButton(
                              icon: const Icon(
                                Icons.save_alt_outlined,
                                semanticLabel: 'Save Current Device Preset',
                              ),
                              tooltip: 'Save Current Device Preset',
                              // Pass manager only if action is possible
                              onPressed: canSave && currentManager != null
                                  ? () => metaCtx
                                        .read<MetadataSyncCubit>()
                                        .saveCurrentPreset(currentManager)
                                  : null,
                            );
                          },
                        ),
                        // --- More Actions Menu ---
                        BlocBuilder<MetadataSyncCubit, MetadataSyncState>(
                          builder: (metaCtx, metaState) {
                            final isMetaBusy =
                                metaState is! ViewingLocalData &&
                                metaState is! Idle &&
                                metaState is! Failure;
                            final isDistingBusy = switch (distingState) {
                              DistingStateSynchronized(loading: final l) => l,
                              _ => false,
                            };
                            final isBusy = isMetaBusy || isDistingBusy;
                            final canSync = isConnected && !isBusy;

                            return PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert,
                                semanticLabel: 'More Actions',
                              ),
                              tooltip: 'More Actions',
                              enabled: !isBusy,
                              onSelected: (value) {
                                switch (value) {
                                  case 'incremental_sync':
                                    if (canSync && currentManager != null) {
                                      _showIncrementalSyncConfirmationDialog(
                                        metaCtx,
                                        currentManager,
                                      );
                                    }
                                    break;
                                  case 'export_algorithms':
                                    _showExportDialog(metaCtx);
                                    break;
                                  case 'template_manager':
                                    final metadataCubit = metaCtx
                                        .read<MetadataSyncCubit>();
                                    Navigator.of(metaCtx).push(
                                      MaterialPageRoute(
                                        builder: (_) => TemplateManagerScreen(
                                          onApplyDevice:
                                              (
                                                template,
                                                selectedIndices,
                                              ) async {
                                                await metadataCubit
                                                    .applyTemplateToDevice(
                                                      template: template,
                                                      templateSlotIndices:
                                                          selectedIndices,
                                                      manager: distingCubit
                                                          .requireDisting(),
                                                    );
                                                final state =
                                                    metadataCubit.state;
                                                if (state
                                                    case PresetLoadFailure(
                                                      error: final error,
                                                    )) {
                                                  throw StateError(error);
                                                }
                                              },
                                          onCancelDeviceApply:
                                              metadataCubit.cancelInjection,
                                          loadCurrentPresetSource: () async =>
                                              fullPresetDetailsFromDistingState(
                                                distingCubit.state,
                                              ),
                                        ),
                                      ),
                                    );
                                    break;
                                  case 'debug_export_full':
                                    if (kDebugMode) {
                                      _showDebugFullExportDialog(metaCtx);
                                    }
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem<String>(
                                  value: 'incremental_sync',
                                  enabled: canSync && currentManager != null,
                                  child: const Row(
                                    children: [
                                      Icon(Icons.sync_alt, size: 20),
                                      SizedBox(width: 12),
                                      Text('Sync New Algorithms Only'),
                                    ],
                                  ),
                                ),
                                const PopupMenuDivider(),
                                PopupMenuItem<String>(
                                  value: 'export_algorithms',
                                  enabled: !isBusy,
                                  child: const Row(
                                    children: [
                                      Icon(Icons.download, size: 20),
                                      SizedBox(width: 12),
                                      Text('Export Algorithm Details'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'template_manager',
                                  enabled: !isBusy,
                                  child: const Row(
                                    children: [
                                      Icon(Icons.dashboard_customize, size: 20),
                                      SizedBox(width: 12),
                                      Text('Template Manager...'),
                                    ],
                                  ),
                                ),
                                if (kDebugMode) ...[
                                  const PopupMenuDivider(),
                                  PopupMenuItem<String>(
                                    value: 'debug_export_full',
                                    enabled: !isBusy,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.bug_report,
                                          size: 20,
                                          color:
                                              context.appColors.warning.color,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'DEBUG: Export Full Metadata',
                                          style: TextStyle(
                                            color:
                                                context.appColors.warning.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                    // Body uses MetadataSyncCubit for DB DistingCubit for state
                    body: MetadataSyncAnnouncementListener(
                      child: BlocBuilder<MetadataSyncCubit, MetadataSyncState>(
                        builder: (metaCtx, metaState) {
                          final isOperationInProgress =
                              metaState is! ViewingLocalData &&
                              metaState is! Idle &&
                              metaState is! Failure;

                          if (metaState is Idle || metaState is LoadingPreset) {
                            // Show spinner if metadata cubit is loading
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (metaState is Failure ||
                              metaState is MetadataSyncFailure ||
                              metaState is PresetSaveFailure ||
                              metaState is PresetDeleteFailure ||
                              metaState is PresetLoadFailure) {
                            final errorMsg = switch (metaState) {
                              Failure(error: final e) => e,
                              MetadataSyncFailure(error: final e) => e,
                              PresetSaveFailure(error: final e) => e,
                              PresetDeleteFailure(error: final e) => e,
                              PresetLoadFailure(error: final e) => e,
                              _ => "An unknown error occurred.",
                            };
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                      size: 48,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(errorMsg, textAlign: TextAlign.center),
                                    const SizedBox(height: 16),
                                    TextButton(
                                      onPressed: () {
                                        // Reset only MetadataSyncCubit, let user handle Disting mode
                                        metaCtx
                                            .read<MetadataSyncCubit>()
                                            .reset();
                                        metaCtx
                                            .read<MetadataSyncCubit>()
                                            .loadLocalData(); // Reload list
                                        // If DistingCubit was also in error, user uses toggle
                                      },
                                      child: const Text("Retry Loading List"),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          if (metaState is CheckpointFound) {
                            return Center(
                              child: _buildCheckpointDialog(context, metaState),
                            );
                          }

                          if (metaState is SyncingMetadata ||
                              metaState is SavingPreset ||
                              metaState is DeletingPreset) {
                            return Center(
                              child: _buildProgressIndicator(
                                context,
                                metaState,
                              ),
                            );
                          }

                          // Primarily use ViewingLocalData state
                          if (metaState is ViewingLocalData) {
                            return _buildDataView(
                              metaCtx,
                              metaState.algorithms,
                              metaState.parameterCounts,
                              metaState.presets,
                              isConnected,
                              isOperationInProgress,
                              isOffline,
                              isOffline &&
                                      currentManager
                                          is OfflineDistingMidiManager
                                  ? currentManager.loadedPresetId
                                  : null,
                            );
                          }
                          // Handle transient success states - might briefly show loading
                          if (metaState is MetadataSyncSuccess ||
                              metaState is PresetSaveSuccess ||
                              metaState is PresetDeleteSuccess ||
                              metaState is PresetLoadSuccess) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          // Fallback - this should rarely occur now
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.warning,
                                  size: 48,
                                  color: metaCtx.appColors.warning.color,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  "Unexpected state: ${metaState.runtimeType}",
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text("Return to Main Screen"),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ), // Scaffold
                ); // PopScope
              }, // BlocBuilder for PopScope
            ), // BlocProvider.value
          );
        },
      ),
    );
  }

  // Progress Indicator Widget
  Widget _buildProgressIndicator(
    BuildContext context,
    MetadataSyncState state,
  ) {
    String mainMessage = "Processing...";
    String? subMessage;
    double? progressValue; // Null for indeterminate
    int? algorithmsProcessed;
    int? totalAlgorithms;

    switch (state) {
      case SyncingMetadata(
        progress: final progress,
        mainMessage: final msg,
        subMessage: final sub,
        algorithmsProcessed: final processed,
        totalAlgorithms: final total,
      ):
        mainMessage = msg;
        subMessage = sub;
        progressValue = progress > 0 ? progress : null;
        algorithmsProcessed = processed;
        totalAlgorithms = total;
        break;
      case SavingPreset():
        mainMessage = "Saving Preset...";
        break;
      case DeletingPreset():
        mainMessage = "Deleting Preset...";
        break;
      default:
        mainMessage = "Please wait...";
        break;
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress bar with enhanced styling
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.shadow
                          .withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: LinearProgressIndicator(
                  value: progressValue,
                  minHeight: 12,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 16),

              // Main message
              Text(
                mainMessage,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              // Progress counter
              if (algorithmsProcessed != null && totalAlgorithms != null) ...[
                const SizedBox(height: 8),
                Text(
                  "Algorithm $algorithmsProcessed of $totalAlgorithms",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              // Sub message with animated dots
              if (subMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        subMessage,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 200,
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.primary,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Action buttons
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () {
                  context.read<MetadataSyncCubit>().cancelMetadataSync();
                },
                icon: const Icon(Icons.close, size: 18),
                label: const Text("Cancel Sync"),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Checkpoint Dialog Widget
  Widget _buildCheckpointDialog(BuildContext context, CheckpointFound state) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restore, size: 48, color: context.appColors.info.color),
            const SizedBox(height: 16),
            const Text(
              'Resume Metadata Sync?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'Found an interrupted sync that was processing "${state.algorithmName}" '
              '(algorithm ${state.algorithmIndex + 1}). Would you like to resume from where you left off?',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () {
                    context.read<MetadataSyncCubit>().declineCheckpoint();
                  },
                  child: const Text('Start Fresh'),
                ),
                ElevatedButton(
                  onPressed: () {
                    context.read<MetadataSyncCubit>().resumeFromCheckpoint();
                    final distingCubit = context.read<DistingCubit>();
                    final manager = distingCubit.disting();
                    if (manager != null) {
                      context.read<MetadataSyncCubit>().startMetadataSync(
                        manager,
                        resumeFromIndex: state.algorithmIndex,
                      );
                    }
                  },
                  child: const Text('Resume'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Confirmation Dialog for Metadata Sync (Manager passed in)
  void _showSyncConfirmationDialog(
    BuildContext metaContext,
    IDistingMidiManager manager,
  ) {
    showDialog(
      context: metaContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Sync Metadata?'),
          content: const Text(
            'This process reads all algorithm data from the device and may require clearing the current preset. Save any work on the device first! Continue?',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Sync'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                // Call cubit with manager
                metaContext.read<MetadataSyncCubit>().startMetadataSync(
                  manager,
                );
              },
            ),
          ],
        );
      },
    );
  }

  // Confirmation Dialog for Incremental Sync (Manager passed in)
  void _showIncrementalSyncConfirmationDialog(
    BuildContext metaContext,
    IDistingMidiManager manager,
  ) {
    showDialog(
      context: metaContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Sync New Algorithms Only?'),
          content: const Text(
            'This will check for algorithms on your device that are not yet in the local database and sync only those new algorithms. This is faster than a full sync but requires that you have already done at least one full sync. Continue?',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Sync New'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                // Call cubit with manager
                metaContext.read<MetadataSyncCubit>().syncNewAlgorithmsOnly(
                  manager,
                );
              },
            ),
          ],
        );
      },
    );
  }

  // Tabbed Data View Widget
  Widget _buildDataView(
    BuildContext builderContext,
    List<AlgorithmEntry> algorithms,
    Map<String, int> parameterCounts,
    List<PresetEntry> presets,
    bool isConnected,
    bool isOperationInProgress,
    bool isOffline,
    int? loadedOfflinePresetId,
  ) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              const Tab(icon: Icon(Icons.save_alt), text: "Saved Presets"),
              StreamBuilder<int>(
                stream: builderContext
                    .read<AppDatabase>()
                    .presetsDao
                    .watchTemplateCount(),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return Tab(
                    icon: Badge(
                      label: Text('$count'),
                      isLabelVisible: count > 0,
                      child: const Icon(Icons.star),
                    ),
                    text: "Templates",
                  );
                },
              ),
              const Tab(icon: Icon(Icons.memory), text: "Synced Algorithms"),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: TabBarView(
                children: [
                  // --- Presets Tab ---
                  _PresetListView(
                    presets: presets,
                    isOperationInProgress: isOperationInProgress,
                    isOffline: isOffline,
                    loadedOfflinePresetId: loadedOfflinePresetId,
                    // Use builderContext to find cubits
                    distingCubit: BlocProvider.of<DistingCubit>(builderContext),
                    metadataSyncCubit: BlocProvider.of<MetadataSyncCubit>(
                      builderContext,
                    ),
                  ),
                  // --- Templates Tab ---
                  _TemplateListView(
                    isOperationInProgress: isOperationInProgress,
                    isOffline: isOffline,
                    loadedOfflinePresetId: loadedOfflinePresetId,
                    distingCubit: BlocProvider.of<DistingCubit>(builderContext),
                    metadataSyncCubit: BlocProvider.of<MetadataSyncCubit>(
                      builderContext,
                    ),
                    database: builderContext.read<AppDatabase>(),
                  ),
                  // --- Algorithms Tab ---
                  _AlgorithmMetadataListView(
                    algorithms: algorithms,
                    parameterCounts: parameterCounts,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Show Export Dialog
  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlgorithmExportDialog(database: context.read<AppDatabase>());
      },
    );
  }

  // Show Debug Full Export Dialog
  void _showDebugFullExportDialog(BuildContext context) {
    if (!kDebugMode) return;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return DebugMetadataExportDialog(database: context.read<AppDatabase>());
      },
    );
  }
}

// --- Widget for Preset List View ---
class _PresetListView extends StatelessWidget {
  final List<PresetEntry> presets;
  final bool isOperationInProgress;
  final bool isOffline;
  final int? loadedOfflinePresetId;
  final DistingCubit distingCubit;
  final MetadataSyncCubit metadataSyncCubit; // Added MetadataSyncCubit

  const _PresetListView({
    required this.presets,
    required this.isOperationInProgress,
    required this.isOffline,
    this.loadedOfflinePresetId,
    required this.distingCubit,
    required this.metadataSyncCubit,
  });

  @override
  Widget build(BuildContext context) {
    if (presets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            "No presets found.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // Sort presets by name for consistent order
    final sortedPresets = List<PresetEntry>.from(presets)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return ListView.separated(
      itemCount: sortedPresets.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1), // Add divider
      itemBuilder: (context, index) {
        final preset = sortedPresets[index];
        final formattedDate = preset.lastModified.toLocal().toString();

        final isCurrentlyLoadedOffline =
            isOffline && loadedOfflinePresetId == preset.id;

        // Determine button states
        final bool canLoad = !isOperationInProgress;
        final bool canDelete = !isOperationInProgress;

        return ListTile(
          key: ValueKey(preset.id),
          selected: isCurrentlyLoadedOffline,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer
              .withValues(alpha: 0.3),
          title: Text(preset.name.trim()),
          subtitle: Text("Saved: $formattedDate"),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Template Toggle Button
              IconButton(
                icon: Icon(
                  preset.isTemplate ? Icons.star : Icons.star_outline,
                  color: preset.isTemplate
                      ? Theme.of(context).colorScheme.tertiary
                      : Theme.of(context).disabledColor,
                  semanticLabel: preset.isTemplate
                      ? 'Unmark as Template'
                      : 'Mark as Template',
                ),
                tooltip: preset.isTemplate
                    ? 'Unmark as Template'
                    : 'Mark as Template',
                onPressed: !isOperationInProgress
                    ? () {
                        context.read<MetadataSyncCubit>().togglePresetTemplate(
                          preset.id,
                          !preset.isTemplate,
                        );
                      }
                    : null,
              ),
              // Load Button (Calls different cubits based on mode)
              IconButton(
                icon: Icon(
                  isOffline ? Icons.edit_note : Icons.upload_file_outlined,
                  color: canLoad
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).disabledColor,
                  semanticLabel: isOffline
                      ? 'Load Preset Offline'
                      : 'Send to NT',
                ),
                tooltip: isOffline ? 'Load Preset Offline' : 'Send to NT',
                onPressed: canLoad
                    ? () =>
                          _showLoadConfirmationDialog(
                            context,
                            preset,
                            isOffline,
                            distingCubit,
                            metadataSyncCubit,
                          ) // Pass both cubits
                    : null,
              ),
              // Delete Button (Calls MetadataSyncCubit)
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: canDelete
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).disabledColor,
                  semanticLabel: 'Delete Saved Preset',
                ),
                tooltip: 'Delete Saved Preset',
                onPressed: canDelete
                    ? () => _showDeleteConfirmationDialog(context, preset)
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }

  // Helper function for Load Confirmation Dialog
  void _showLoadConfirmationDialog(
    BuildContext context, // BuildContext from ListView item
    PresetEntry preset,
    bool isOffline,
    DistingCubit distingCubit,
    MetadataSyncCubit metadataSyncCubit, // Pass both cubits
  ) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
            isOffline ? 'Load Preset Offline?' : 'Send Preset to NT?',
          ),
          content: Text(
            isOffline
                ? 'Load "${preset.name}" for offline use?' // Simplified message
                : 'Send "${preset.name}" to device? This overwrites current device state.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: Text(isOffline ? 'Load Offline' : 'Send'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                // Pop the dialog first
                Navigator.of(dialogContext).pop();
                try {
                  // Fetch full details (still needed)
                  final fullDetails =
                      await context // Use outer context for DB
                          .read<AppDatabase>()
                          .presetsDao
                          .getFullPresetDetails(preset.id);

                  if (fullDetails != null) {
                    // Call correct Cubit based on mode
                    if (isOffline) {
                      await distingCubit.loadPresetOffline(fullDetails);
                      // After loading offline, pop the metadata page
                      // Use the original context from the list item builder
                      if (context.mounted) {
                        // Check if the widget is still mounted
                        Navigator.of(context).pop();
                      }
                      final manager = distingCubit.disting();
                      if (manager is OfflineDistingMidiManager &&
                          manager.unavailableSlotIndices.isNotEmpty) {
                        final unavailable = manager.unavailableSlotIndices;
                        final guids = unavailable
                            .map(
                              (index) =>
                                  fullDetails.slots[index].algorithm.guid,
                            )
                            .join(', ');
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              '${unavailable.length} algorithm(s) unavailable offline '
                              '($guids). Kept in original slots; saved data preserved.',
                            ),
                          ),
                        );
                      }
                    } else {
                      // Need manager instance for online load
                      final onlineManager = distingCubit.disting();
                      if (onlineManager != null) {
                        metadataSyncCubit.loadPresetToDevice(
                          fullDetails,
                          onlineManager,
                        );
                      } else {
                        // Should not happen if button is enabled correctly
                        throw Exception(
                          "Cannot load preset: Online manager not available.",
                        );
                      }
                    }
                  } else {
                    // Show error if details couldn't be loaded
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).removeCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "Error: Could not load details for preset '${preset.name}'",
                          ),
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  // Show error if fetching/loading failed
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).removeCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "Error fetching/loading preset details: $e",
                        ),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  // Helper function for Delete Confirmation Dialog (Uses MetadataSyncCubit)
  void _showDeleteConfirmationDialog(BuildContext context, PresetEntry preset) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete Preset?'),
          content: Text(
            'Are you sure you want to permanently delete the saved preset "${preset.name}"?',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                // Delete uses MetadataSyncCubit from context
                context.read<MetadataSyncCubit>().deletePreset(preset.id);
              },
            ),
          ],
        );
      },
    );
  }

  // Helper function for Template Toggle Menu
}

// --- Widget for Template List View ---
class _TemplateListView extends StatelessWidget {
  final bool isOperationInProgress;
  final bool isOffline;
  final int? loadedOfflinePresetId;
  final DistingCubit distingCubit;
  final MetadataSyncCubit metadataSyncCubit;
  final AppDatabase database;

  const _TemplateListView({
    required this.isOperationInProgress,
    required this.isOffline,
    this.loadedOfflinePresetId,
    required this.distingCubit,
    required this.metadataSyncCubit,
    required this.database,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FullPresetDetails>>(
      future: database.presetsDao.getTemplates(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                "Error loading templates: ${snapshot.error}",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          );
        }

        final templates = snapshot.data ?? [];

        if (templates.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.star_border,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "No templates found. Mark saved presets as templates to see them here.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: [
                  Text(
                    '${templates.length} template${templates.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Open Template Manager',
                    icon: const Icon(Icons.dashboard_customize),
                    onPressed: isOperationInProgress
                        ? null
                        : () {
                            final metadataCubit = context
                                .read<MetadataSyncCubit>();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => TemplateManagerScreen(
                                  onApplyDevice:
                                      (template, selectedIndices) async {
                                        await metadataCubit
                                            .applyTemplateToDevice(
                                              template: template,
                                              templateSlotIndices:
                                                  selectedIndices,
                                              manager: distingCubit
                                                  .requireDisting(),
                                            );
                                        final state = metadataCubit.state;
                                        if (state case PresetLoadFailure(
                                          error: final error,
                                        )) {
                                          throw StateError(error);
                                        }
                                      },
                                  onCancelDeviceApply:
                                      metadataCubit.cancelInjection,
                                  loadCurrentPresetSource: () async =>
                                      fullPresetDetailsFromDistingState(
                                        distingCubit.state,
                                      ),
                                ),
                              ),
                            );
                          },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: templates.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final template = templates[index];
                  final preset = template.preset;
                  final formattedDate = preset.lastModified
                      .toLocal()
                      .toString();

                  final isCurrentlyLoadedOffline =
                      isOffline && loadedOfflinePresetId == preset.id;

                  // Determine button states
                  final bool canLoad = !isOperationInProgress;
                  final bool canDelete = !isOperationInProgress;

                  return ListTile(
                    key: ValueKey(preset.id),
                    selected: isCurrentlyLoadedOffline,
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.3),
                    leading: Icon(
                      Icons.star,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    title: Text(preset.name.trim()),
                    subtitle: Text("Saved: $formattedDate"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Inject Button
                        IconButton(
                          icon: Icon(
                            Icons.add_circle_outline,
                            color: canLoad
                                ? Theme.of(context).colorScheme.secondary
                                : Theme.of(context).disabledColor,
                            semanticLabel: isOffline
                                ? 'Inject Template (Offline)'
                                : 'Inject Template',
                          ),
                          tooltip: isOffline
                              ? 'Inject Template (Offline)'
                              : 'Inject Template',
                          onPressed: canLoad
                              ? () async => await _showInjectDialog(
                                  context,
                                  template,
                                  distingCubit,
                                  metadataSyncCubit,
                                )
                              : null,
                        ),
                        // Load Button
                        IconButton(
                          icon: Icon(
                            isOffline
                                ? Icons.edit_note
                                : Icons.upload_file_outlined,
                            color: canLoad
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).disabledColor,
                            semanticLabel: isOffline
                                ? 'Load Preset Offline'
                                : 'Send to NT',
                          ),
                          tooltip: isOffline
                              ? 'Load Preset Offline'
                              : 'Send to NT',
                          onPressed: canLoad
                              ? () => _showLoadConfirmationDialog(
                                  context,
                                  template,
                                  isOffline,
                                  distingCubit,
                                  metadataSyncCubit,
                                )
                              : null,
                        ),
                        // Delete Button
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: canDelete
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).disabledColor,
                            semanticLabel: 'Delete Template',
                          ),
                          tooltip: 'Delete Template',
                          onPressed: canDelete
                              ? () => _showDeleteConfirmationDialog(
                                  context,
                                  preset,
                                )
                              : null,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // Helper function for Load Confirmation Dialog
  void _showLoadConfirmationDialog(
    BuildContext context,
    FullPresetDetails template,
    bool isOffline,
    DistingCubit distingCubit,
    MetadataSyncCubit metadataSyncCubit,
  ) {
    final preset = template.preset;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
            isOffline ? 'Load Template Offline?' : 'Send Template to NT?',
          ),
          content: Text(
            isOffline
                ? 'Load "${preset.name}" for offline use?'
                : 'Send "${preset.name}" to device? This overwrites current device state.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: Text(isOffline ? 'Load Offline' : 'Send'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.of(dialogContext).pop();
                if (isOffline) {
                  await distingCubit.loadPresetOffline(template);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                  final manager = distingCubit.disting();
                  if (manager is OfflineDistingMidiManager &&
                      manager.unavailableSlotIndices.isNotEmpty) {
                    final unavailable = manager.unavailableSlotIndices;
                    final guids = unavailable
                        .map((index) => template.slots[index].algorithm.guid)
                        .join(', ');
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          '${unavailable.length} algorithm(s) unavailable offline '
                          '($guids). Kept in original slots; saved data preserved.',
                        ),
                      ),
                    );
                  }
                } else {
                  final onlineManager = distingCubit.disting();
                  if (onlineManager != null) {
                    metadataSyncCubit.loadPresetToDevice(
                      template,
                      onlineManager,
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  // Helper function for Delete Confirmation Dialog
  void _showDeleteConfirmationDialog(BuildContext context, PresetEntry preset) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete Template?'),
          content: Text(
            'Are you sure you want to permanently delete the template "${preset.name}"?',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                metadataSyncCubit.deletePreset(preset.id);
              },
            ),
          ],
        );
      },
    );
  }

  // Helper function for Inject Template Dialog
  Future<void> _showInjectDialog(
    BuildContext context,
    FullPresetDetails template,
    DistingCubit distingCubit,
    MetadataSyncCubit metadataSyncCubit,
  ) async {
    // Check for empty template first
    if (template.slots.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot inject empty template'),
            backgroundColor: context.appColors.warning.color,
          ),
        );
      }
      return;
    }

    final manager = distingCubit.disting();
    if (manager == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Device not connected'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    // Get current slot count from device
    int currentSlotCount = 0;
    try {
      currentSlotCount = await manager.requestNumAlgorithmsInPreset() ?? 0;
    } catch (e) {
      // In offline/demo mode, assume empty preset
      currentSlotCount = 0;
    }

    if (!context.mounted) return;

    // Show confirmation dialog for large templates (> 10 algorithms)
    if (template.slots.length > 10) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Large Template'),
          content: Text(
            'This will add ${template.slots.length} algorithms to your preset. Continue?',
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            ElevatedButton(
              child: const Text('Continue'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
      if (!context.mounted) return;
    }

    // Show the template preview dialog. Successful injection refreshes
    // DistingCubit centrally in MetadataSyncCubit.applyTemplateToDevice().
    await TemplatePreviewDialog.show(
      context,
      template,
      currentSlotCount,
      metadataSyncCubit,
      manager,
    );
  }
}

// --- Widget for Algorithm Metadata List View (Stateful for filtering) ---
class _AlgorithmMetadataListView extends StatefulWidget {
  final List<AlgorithmEntry> algorithms;
  final Map<String, int> parameterCounts;

  const _AlgorithmMetadataListView({
    required this.algorithms,
    required this.parameterCounts, // Added key
  });

  @override
  State<_AlgorithmMetadataListView> createState() =>
      _AlgorithmMetadataListViewState();
}

class _AlgorithmMetadataListViewState
    extends State<_AlgorithmMetadataListView> {
  late final TextEditingController _filterController;
  late List<AlgorithmEntry> _filteredAlgorithms;

  @override
  void initState() {
    super.initState();
    _filterController = TextEditingController();
    // Initialize with all algorithms sorted
    _filteredAlgorithms = _sortAlgorithms(widget.algorithms);

    _filterController.addListener(_filterList);
  }

  @override
  void didUpdateWidget(covariant _AlgorithmMetadataListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the underlying algorithm list changes, re-apply filter
    if (widget.algorithms != oldWidget.algorithms) {
      _filterList();
    }
  }

  @override
  void dispose() {
    _filterController.removeListener(_filterList);
    _filterController.dispose();
    super.dispose();
  }

  // Helper to sort algorithms by name
  List<AlgorithmEntry> _sortAlgorithms(List<AlgorithmEntry> algorithms) {
    final sorted = List<AlgorithmEntry>.from(algorithms)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return sorted;
  }

  void _filterList() {
    final query = _filterController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredAlgorithms = _sortAlgorithms(widget.algorithms);
      } else {
        _filteredAlgorithms = _sortAlgorithms(
          widget.algorithms
              .where((algo) => algo.name.toLowerCase().contains(query))
              .toList(),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Handle the case where the initial list might be empty
    if (widget.algorithms.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text(
            "No algorithms found. Connect your NT and perform a 'Sync From Device'.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: DigitShortcutBlocker(
            child: TextField(
              controller: _filterController,
              decoration: InputDecoration(
                labelText: "Filter Algorithms",
                hintText: "Enter algorithm name...",
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                // Add clear button
                suffixIcon: _filterController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear,
                          semanticLabel: 'Clear filter',
                        ),
                        onPressed: () {
                          _filterController.clear();
                          // _filterList will be called by the listener
                        },
                      )
                    : null,
              ),
            ),
          ),
        ),
        Expanded(
          // Display message if filter results are empty
          child: _filteredAlgorithms.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Text(
                      'No algorithms match "${_filterController.text}".',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _filteredAlgorithms.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final algo = _filteredAlgorithms[index];
                    final count = widget.parameterCounts[algo.guid] ?? 0;
                    return _AlgorithmExpansionTile(
                      algorithm: algo,
                      parameterCount: count,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// --- StatefulWidget for Algorithm Expansion Tile ---
class _AlgorithmExpansionTile extends StatefulWidget {
  final AlgorithmEntry algorithm;
  final int parameterCount;

  const _AlgorithmExpansionTile({
    required this.algorithm,
    required this.parameterCount,
  });

  @override
  State<_AlgorithmExpansionTile> createState() =>
      _AlgorithmExpansionTileState();
}

class _AlgorithmExpansionTileState extends State<_AlgorithmExpansionTile> {
  bool _isLoading = false;
  bool _isRescanning = false;
  List<ParameterWithUnit>? _parameters;
  String? _error;

  Future<void> _fetchParameters({bool forceRefresh = false}) async {
    if (_isLoading) return;

    // Skip if we already have parameters and this isn't a forced refresh
    if (_parameters != null && !forceRefresh) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dao = context.read<AppDatabase>().metadataDao;
      final details = await dao.getFullAlgorithmDetails(widget.algorithm.guid);

      if (mounted) {
        setState(() {
          _parameters = details?.parameters ?? [];
          _isLoading = false;
          if (_parameters!.isEmpty && widget.parameterCount > 0) {
            _error =
                "Parameter count is ${widget.parameterCount}, but no parameters were loaded.";
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Failed to load parameters: ${e.toString()}";
        });
      }
    }
  }

  Future<void> _rescanAlgorithm() async {
    if (_isRescanning) return;

    final distingCubit = context.read<DistingCubit>();
    final manager = distingCubit.disting();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final database = context.read<AppDatabase>();
    final metadataCubit = context.read<MetadataSyncCubit>();

    if (manager == null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text("Device not connected"),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() {
      _isRescanning = true;
      _error = null;
    });

    try {
      // Use the metadata sync service directly for the rescan
      final syncService = MetadataSyncService(manager, database);

      // Find the algorithm info from the database
      final dao = database.metadataDao;
      final algorithm = await dao.getAlgorithmByGuid(widget.algorithm.guid);
      if (algorithm == null) {
        throw Exception("Algorithm not found in database");
      }

      // Get algorithm info from device
      final numAlgoTypes = await manager.requestNumberOfAlgorithms();
      if (numAlgoTypes == null) {
        throw Exception("Failed to get algorithm count from device");
      }

      AlgorithmInfo? targetAlgoInfo;
      for (int i = 0; i < numAlgoTypes; i++) {
        final algoInfo = await manager.requestAlgorithmInfo(i);
        if (algoInfo?.guid == widget.algorithm.guid) {
          targetAlgoInfo = algoInfo;
          break;
        }
      }

      if (targetAlgoInfo == null) {
        throw Exception("Algorithm not found on device");
      }

      // Perform the rescan using the service
      await syncService.rescanSingleAlgorithm(targetAlgoInfo);

      if (mounted) {
        // Refresh the parameters after successful rescan
        setState(() {
          _parameters = null; // Clear cache to force reload
          _isRescanning = false;
        });

        // Trigger a reload of the entire algorithm list in the parent cubit
        // This will update parameter counts and cause the widget to rebuild
        await metadataCubit.loadLocalData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRescanning = false;
          _error = "Rescan failed: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MetadataSyncCubit, MetadataSyncState>(
      listener: (context, state) {
        // If we just completed a metadata sync successfully, refresh parameters
        // Only needed for expandable tiles (parameterCount > 0)
        if ((state is MetadataSyncSuccess || state is ViewingLocalData) &&
            widget.parameterCount > 0) {
          // Only refresh if this tile is expanded and has cached parameters
          if (_parameters != null) {
            _fetchParameters(forceRefresh: true);
          }
        }
      },
      child: widget.parameterCount == 0
          ? ListTile(
              key: PageStorageKey(widget.algorithm.guid),
              title: Text(
                "${widget.algorithm.name} [${widget.algorithm.guid}]",
              ),
              subtitle: Text("Params: ${widget.parameterCount}"),
              trailing: _isRescanning
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : InkWell(
                      onTap: _rescanAlgorithm,
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(Icons.refresh, size: 24),
                      ),
                    ),
            )
          : ExpansionTile(
              key: PageStorageKey(widget.algorithm.guid),
              title: Text(
                "${widget.algorithm.name} [${widget.algorithm.guid}]",
              ),
              subtitle: Text("Params: ${widget.parameterCount}"),
              childrenPadding: const EdgeInsets.only(
                left: 32.0,
                right: 16.0,
                bottom: 8.0,
              ),
              onExpansionChanged: (isExpanding) {
                if (isExpanding && _parameters == null && !_isLoading) {
                  _fetchParameters();
                }
              },
              children: [
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                if (_parameters != null && !_isLoading && _error == null)
                  if (_parameters!.isEmpty && widget.parameterCount > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Center(
                        child: Text(
                          "No parameters found.",
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ),
                    )
                  else if (_parameters!.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _parameters!.map((paramWithUnit) {
                        final param = paramWithUnit.parameter;
                        final pageName =
                            paramWithUnit.pageName ?? 'Unknown Page';

                        return ListTile(
                          isThreeLine: true,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            param.name,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Page: $pageName (#${param.parameterNumber})",
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                "Range: ${param.minValue ?? '-'} to ${param.maxValue ?? '-'} (Def: ${param.defaultValue ?? '-'}), Unit: ${paramWithUnit.unitString ?? '-'}",
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Center(
                        child: Text(
                          "Algorithm has parameters but they couldn't be displayed.",
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}
