import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/models/firmware_version.dart';

class DistingVersion extends StatelessWidget {
  const DistingVersion({
    super.key,
    required this.distingVersion,
    required this.requiredVersion,
    this.firmwareVersion,
    this.firmwareDate,
    this.onTap,
    this.onHelpTextChanged,
  });

  final String distingVersion;
  final String requiredVersion;
  final FirmwareVersion? firmwareVersion;
  final String? firmwareDate;
  final VoidCallback? onTap;
  final ValueChanged<String?>? onHelpTextChanged;

  static const String firmwareHelpText = 'Tap: Manage firmware updates';

  @override
  Widget build(BuildContext context) {
    final versionToCheck = firmwareVersion ?? FirmwareVersion(distingVersion);
    final isNotSupported = !versionToCheck.isSupported(requiredVersion);

    final versionStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: isNotSupported
          ? Theme.of(context).colorScheme.error
          : Theme.of(context).colorScheme.onSurfaceVariant,
    );

    final Widget text = firmwareDate != null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(distingVersion, style: versionStyle),
              Text(firmwareDate!, style: versionStyle),
            ],
          )
        : Text(distingVersion, style: versionStyle);

    // Only show tooltip if contextual help is not available
    final showTooltip = onHelpTextChanged == null;
    final tooltipMessage = isNotSupported
        ? "nt_helper requires at least $requiredVersion"
        : onTap != null
        ? "Tap to manage firmware"
        : "";

    Widget content = text;
    if (showTooltip && tooltipMessage.isNotEmpty) {
      content = Tooltip(message: tooltipMessage, child: text);
    }

    final dateLabel = firmwareDate != null ? ', date $firmwareDate' : '';
    final wrappedContent = Semantics(
      label: isNotSupported
          ? 'Firmware version $distingVersion$dateLabel - update required, minimum $requiredVersion'
          : 'Firmware version $distingVersion$dateLabel',
      button: onTap != null,
      hint: onTap != null ? 'Tap to manage firmware updates' : null,
      excludeSemantics: true,
      child: content,
    );

    if (onTap != null) {
      return MouseRegion(
        onEnter: (_) => onHelpTextChanged?.call(firmwareHelpText),
        onExit: (_) => onHelpTextChanged?.call(null),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: wrappedContent,
          ),
        ),
      );
    }

    return wrappedContent;
  }
}
