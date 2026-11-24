import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/core/routing/ntx8cv_routing.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/models/device_io_profile.dart';

class Ntx8cvRoutingFrame extends StatelessWidget {
  const Ntx8cvRoutingFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<RoutingEditorCubit, RoutingEditorState>(
        buildWhen: (a, b) =>
            a is! RoutingEditorStateLoaded ||
            b is! RoutingEditorStateLoaded ||
            a.ntx8cvRouting != b.ntx8cvRouting ||
            a.deviceIoProfile != b.deviceIoProfile,
        builder: (context, state) => Column(
          children: [
            Expanded(child: child),
            ExcludeFocus(
              excluding:
                  state is! RoutingEditorStateLoaded ||
                  state.ntx8cvRouting == null,
              child: Visibility(
                visible:
                    state is RoutingEditorStateLoaded &&
                    state.ntx8cvRouting != null,
                maintainSize: true,
                maintainState: true,
                maintainAnimation: true,
                child: Ntx8cvRoutingOutputs(
                  config: state is RoutingEditorStateLoaded
                      ? state.ntx8cvRouting ?? const Ntx8cvRouting.unresolved()
                      : const Ntx8cvRouting.unresolved(),
                  profile:
                      state is RoutingEditorStateLoaded &&
                          state.ntx8cvRouting != null
                      ? state.deviceIoProfile
                      : DeviceIoProfile.distingExtended,
                  reserveOnly:
                      state is! RoutingEditorStateLoaded ||
                      state.ntx8cvRouting == null,
                ),
              ),
            ),
          ],
        ),
      );
}

class Ntx8cvRoutingOutputs extends StatelessWidget {
  const Ntx8cvRoutingOutputs({
    super.key,
    required this.config,
    required this.profile,
    this.reserveOnly = false,
  });

  /// Measures the same row height without creating hidden scroll targets.
  final bool reserveOnly;
  final Ntx8cvRouting config;
  final DeviceIoProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Tooltip(
                message: config.description,
                child: Text(
                  config.scopeLabel,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Builder(
              builder: (context) {
                final row = Row(
                  children: [
                    for (final port
                        in config.ports(profile).take(reserveOnly ? 1 : 8))
                      Semantics(
                        label: port.description,
                        child: Focus(
                          child: Tooltip(
                            message: port.description!,
                            child: Container(
                              key: ValueKey(
                                'ntx8cv_summary_${port.hardwareIndex}',
                              ),
                              width: 116,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                              child: ExcludeSemantics(
                                child: Text(
                                  '${port.name} · ${profile.labelForBus(port.busValue!)}${!config.available
                                      ? ' ?'
                                      : !port.isActive
                                      ? ' —'
                                      : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
                return reserveOnly
                    ? row
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: row,
                      );
              },
            ),
          ],
        ),
      ),
    );
  }
}
