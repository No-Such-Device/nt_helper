import 'package:material_ui/material_ui.dart';

/// Compact settings-row control for selecting an opaque Material theme seed.
class ThemeSeedPicker extends StatelessWidget {
  const ThemeSeedPicker({
    super.key,
    required this.value,
    required this.defaultValue,
    required this.onChanged,
  });

  final Color value;
  final Color defaultValue;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hex = formatThemeColorHex(value);
    final isDefault = value.toARGB32() == defaultValue.toARGB32();

    return Row(
      children: [
        Expanded(
          child: Text('Theme Colour', style: theme.textTheme.titleMedium),
        ),
        Text(hex, style: theme.textTheme.bodyMedium),
        const SizedBox(width: 10),
        Semantics(
          button: true,
          label: 'Choose theme colour. Current colour $hex',
          child: Tooltip(
            message: 'Choose theme colour',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _chooseColor(context),
                child: Container(
                  key: const ValueKey('theme-seed-swatch'),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: value,
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.outline),
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('reset-theme-seed'),
          tooltip: 'Reset theme colour',
          icon: const Icon(Icons.refresh),
          onPressed: isDefault ? null : () => onChanged(defaultValue),
        ),
      ],
    );
  }

  Future<void> _chooseColor(BuildContext context) async {
    final selected = await showDialog<Color>(
      context: context,
      builder: (context) => _MaterialSeedColorDialog(initialColor: value),
    );
    if (selected != null) onChanged(selected);
  }
}

String formatThemeColorHex(Color color) {
  final rgb = color.toARGB32() & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class _MaterialSeedColorDialog extends StatefulWidget {
  const _MaterialSeedColorDialog({required this.initialColor});

  final Color initialColor;

  @override
  State<_MaterialSeedColorDialog> createState() =>
      _MaterialSeedColorDialogState();
}

class _MaterialSeedColorDialogState extends State<_MaterialSeedColorDialog> {
  late Color _selectedColor;
  late int _selectedFamilyIndex;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
    _selectedFamilyIndex = _familyIndexFor(widget.initialColor) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final family = _materialFamilies[_selectedFamilyIndex];

    return AlertDialog(
      title: Semantics(header: true, child: const Text('Choose Theme Colour')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: FocusTraversalGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Colour family', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (
                      var index = 0;
                      index < _materialFamilies.length;
                      index++
                    )
                      _ColorSwatchButton(
                        color: _materialFamilies[index].representative,
                        label: _materialFamilies[index].name,
                        selected: index == _selectedFamilyIndex,
                        onTap: () {
                          setState(() {
                            _selectedFamilyIndex = index;
                            _selectedColor =
                                _materialFamilies[index].representative;
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  '${family.name} shades',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final shade in family.shades.entries)
                      _ColorSwatchButton(
                        color: shade.value,
                        label: '${family.name} ${shade.key}',
                        selected:
                            shade.value.toARGB32() == _selectedColor.toARGB32(),
                        onTap: () {
                          setState(() => _selectedColor = shade.value);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _selectedColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.colorScheme.outline),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Selected ${formatThemeColorHex(_selectedColor)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selectedColor),
          child: const Text('Select'),
        ),
      ],
    );
  }
}

class _ColorSwatchButton extends StatelessWidget {
  const _ColorSwatchButton({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Semantics(
      button: true,
      selected: selected,
      label: '$label, ${formatThemeColorHex(color)}',
      child: Tooltip(
        message: label,
        child: Material(
          color: color,
          shape: CircleBorder(
            side: BorderSide(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 36,
              child: selected
                  ? Icon(Icons.check, size: 20, color: foreground)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _MaterialFamily {
  const _MaterialFamily({
    required this.name,
    required this.representative,
    required this.shades,
  });

  final String name;
  final Color representative;
  final Map<int, Color> shades;
}

const _primaryNames = <String>[
  'Red',
  'Pink',
  'Purple',
  'Deep purple',
  'Indigo',
  'Blue',
  'Light blue',
  'Cyan',
  'Teal',
  'Green',
  'Light green',
  'Lime',
  'Yellow',
  'Amber',
  'Orange',
  'Deep orange',
  'Brown',
  'Blue grey',
];

const _accentNames = <String>[
  'Red accent',
  'Pink accent',
  'Purple accent',
  'Deep purple accent',
  'Indigo accent',
  'Blue accent',
  'Light blue accent',
  'Cyan accent',
  'Teal accent',
  'Green accent',
  'Light green accent',
  'Lime accent',
  'Yellow accent',
  'Amber accent',
  'Orange accent',
  'Deep orange accent',
];

final List<_MaterialFamily> _materialFamilies = <_MaterialFamily>[
  for (var index = 0; index < Colors.primaries.length; index++)
    _MaterialFamily(
      name: _primaryNames[index],
      representative: Colors.primaries[index].shade500,
      shades: <int, Color>{
        for (final shade in const <int>[
          50,
          100,
          200,
          300,
          400,
          500,
          600,
          700,
          800,
          900,
        ])
          shade: Colors.primaries[index][shade]!,
      },
    ),
  for (var index = 0; index < Colors.accents.length; index++)
    _MaterialFamily(
      name: _accentNames[index],
      representative: Colors.accents[index].shade200,
      shades: <int, Color>{
        for (final shade in const <int>[100, 200, 400, 700])
          shade: Colors.accents[index][shade]!,
      },
    ),
];

int? _familyIndexFor(Color color) {
  for (var index = 0; index < _materialFamilies.length; index++) {
    if (_materialFamilies[index].shades.values.any(
      (candidate) => candidate.toARGB32() == color.toARGB32(),
    )) {
      return index;
    }
  }
  return null;
}
