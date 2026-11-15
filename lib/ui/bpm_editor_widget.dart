import 'dart:async'; // For Timer
import 'dart:math'; // For pow()

import 'package:flutter/gestures.dart'; // For kDoubleTapTimeout

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:nt_helper/services/settings_service.dart'; // Required for Haptics and SettingsService

// New BPM Editor Widget
class BpmEditorWidget extends StatefulWidget {
  final int initialValue;
  final int min;
  final int max;
  final int powerOfTen;
  final Function(int) onChanged;
  final Function(bool) onEditingStatusChanged; // To inform parent about focus

  const BpmEditorWidget({
    super.key,
    required this.initialValue,
    required this.min,
    required this.max,
    required this.powerOfTen,
    required this.onChanged,
    required this.onEditingStatusChanged,
  });

  @override
  State<BpmEditorWidget> createState() => _BpmEditorWidgetState();
}

class _BpmEditorWidgetState extends State<BpmEditorWidget> {
  late TextEditingController _textController;
  late int _currentBpm;
  final FocusNode _focusNode = FocusNode();

  Timer? _longPressAccelerationTimer;
  double _accelerationMultiplier = 1.0;
  static const Duration _initialAccelerationDelay = Duration(milliseconds: 500);
  static const Duration _acceleratingInterval = Duration(
    milliseconds: 200,
  ); // Slowed down from 80ms
  static const double _maxAccelerationMultiplier =
      10.0; // Reduced max from 20 to 10
  static const double _accelerationRate =
      1.15; // Reduced from 1.25 for slower acceleration

  int _accelerationStepCount = 0;
  static const int _stepsBeforeAcceleration =
      5; // Number of steps at constant speed before acceleration starts

  Timer? _tapVerificationTimer; // Timer to verify if tap becomes long press
  bool _didPerformInitialStep = false; // Track if onTapDown executed a step
  bool _initialStepWasIncrement =
      false; // Track the direction of the initial step

  @override
  void initState() {
    super.initState();
    _currentBpm = widget.initialValue;
    _textController = TextEditingController(
      text: _formatBpmForDisplay(_currentBpm),
    );
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(BpmEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _currentBpm && !_focusNode.hasFocus) {
      _currentBpm = widget.initialValue;
      _textController.text = _formatBpmForDisplay(_currentBpm);
    }
  }

  void _handleFocusChange() {
    widget.onEditingStatusChanged(_focusNode.hasFocus);
    if (!_focusNode.hasFocus) {
      _validateAndSubmit();
    }
  }

  // Display scaled value accounting for powerOfTen
  // powerOfTen is negative (e.g., -2 means divide raw by 100)
  String _formatBpmForDisplay(int rawBpm) {
    final displayValue = rawBpm * pow(10, widget.powerOfTen);
    // For negative powerOfTen, show decimal places; for zero/positive, show integer
    if (widget.powerOfTen < 0) {
      return displayValue.toStringAsFixed(widget.powerOfTen.abs());
    }
    return displayValue.round().toString();
  }

  void _validateAndSubmit() {
    final textValue = _textController.text;
    double? parsedValue = double.tryParse(textValue);

    if (parsedValue != null) {
      // Convert display value back to raw internal value
      // Divide by 10^powerOfTen (equivalent to multiply by 10^(-powerOfTen))
      int newRawBpm = (parsedValue / pow(10, widget.powerOfTen)).round();

      newRawBpm = newRawBpm.clamp(widget.min, widget.max);

      if (newRawBpm != _currentBpm) {
        setState(() {
          _currentBpm = newRawBpm;
        });
        widget.onChanged(_currentBpm);
      }
      // Always update text controller to reflect clamped and correctly formatted value
      _textController.text = _formatBpmForDisplay(_currentBpm);
    } else {
      // If parsing fails, revert to the last valid BPM, correctly formatted
      _textController.text = _formatBpmForDisplay(_currentBpm);
    }
  }

  // Step by one display unit for each increment/decrement
  void _performSingleStep(bool increment, {bool isUndo = false}) {
    // If it's an undo, we reverse the original direction
    bool actualIncrement = isUndo ? !_initialStepWasIncrement : increment;

    // Step by 10^(-powerOfTen) to change display value by 1
    // e.g., powerOfTen=-2 means step by 100 raw units to change display by 1
    int stepSize = pow(10, -widget.powerOfTen).round();

    if (actualIncrement) {
      if (_currentBpm < widget.max) {
        setState(() {
          _currentBpm = min(_currentBpm + stepSize, widget.max);
          _textController.text = _formatBpmForDisplay(_currentBpm);
        });
        if (!isUndo) widget.onChanged(_currentBpm);
      }
    } else {
      if (_currentBpm > widget.min) {
        setState(() {
          _currentBpm = max(_currentBpm - stepSize, widget.min);
          _textController.text = _formatBpmForDisplay(_currentBpm);
        });
        if (!isUndo) widget.onChanged(_currentBpm);
      }
    }
    // Haptics only for initial, non-undo actions, triggered by onTapDown directly
  }

  void _handleIconButtonTap(bool increment) {
    if (SettingsService().hapticsEnabled) Haptics.vibrate(HapticsType.light);

    _performSingleStep(increment);
    _didPerformInitialStep = true;
    _initialStepWasIncrement = increment;

    _tapVerificationTimer?.cancel();
    _tapVerificationTimer = Timer(kDoubleTapTimeout, () {
      _didPerformInitialStep = false;
    });
  }

  void _startAcceleratedChange(bool increment) {
    _tapVerificationTimer?.cancel();

    if (_didPerformInitialStep) {
      _performSingleStep(!_initialStepWasIncrement, isUndo: true);
      _didPerformInitialStep = false;
    }

    _stopAcceleratedChange(performSnap: false);
    _accelerationMultiplier = 1.0;
    _accelerationStepCount = 0;

    _longPressAccelerationTimer = Timer.periodic(_initialAccelerationDelay, (
      timerAfterDelay,
    ) {
      timerAfterDelay.cancel();
      _performAcceleratedStep(increment);
      _longPressAccelerationTimer = Timer.periodic(_acceleratingInterval, (_) {
        _performAcceleratedStep(increment);
      });
    });
  }

  void _performAcceleratedStep(bool increment) {
    if (!mounted) {
      _stopAcceleratedChange(performSnap: false);
      return;
    }

    // Increment the step count
    _accelerationStepCount++;

    // Only start accelerating after certain number of steps
    if (_accelerationStepCount > _stepsBeforeAcceleration) {
      if (_accelerationMultiplier < _maxAccelerationMultiplier) {
        _accelerationMultiplier = min(
          _accelerationMultiplier * _accelerationRate,
          _maxAccelerationMultiplier,
        );
      }
    }

    // Step by 10^(-powerOfTen) * accelerationMultiplier
    int stepSize = (pow(10, -widget.powerOfTen) * _accelerationMultiplier)
        .round();

    // Ensure minimum step size is at least one display unit
    stepSize = max(stepSize, pow(10, -widget.powerOfTen).round());

    setState(() {
      if (increment) {
        _currentBpm = min(_currentBpm + stepSize, widget.max);
      } else {
        _currentBpm = max(_currentBpm - stepSize, widget.min);
      }
      _textController.text = _formatBpmForDisplay(_currentBpm);
    });

    widget.onChanged(_currentBpm);

    // Only vibrate on certain steps to avoid excessive haptics
    if (_accelerationStepCount % 2 == 0 && SettingsService().hapticsEnabled) {
      Haptics.vibrate(HapticsType.selection);
    }

    if ((increment && _currentBpm == widget.max) ||
        (!increment && _currentBpm == widget.min)) {
      _stopAcceleratedChange(performSnap: false);
    }
  }

  void _stopAcceleratedChange({required bool performSnap}) {
    _longPressAccelerationTimer?.cancel();
    _longPressAccelerationTimer = null;
    _didPerformInitialStep = false;
    _accelerationMultiplier = 1.0;
    _accelerationStepCount = 0;
  }

  @override
  Widget build(BuildContext context) {
    bool widescreen = MediaQuery.of(context).size.width > 600;
    final textStyle = widescreen
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.titleSmall;
    final iconSize = widescreen ? 28.0 : 24.0;
    final splashRadius = widescreen ? 28.0 : 24.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onLongPressStart: (_) => _startAcceleratedChange(false),
          onLongPressEnd: (_) => _stopAcceleratedChange(performSnap: true),
          onLongPressCancel: () => _stopAcceleratedChange(performSnap: false),
          child: IconButton(
            icon: const Icon(
              Icons.remove_circle_outline,
              semanticLabel: 'Decrease BPM',
            ),
            iconSize: iconSize,
            splashRadius: splashRadius,
            tooltip: 'Decrease BPM',
            onPressed: () => _handleIconButtonTap(false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Shortcuts(
                shortcuts: <ShortcutActivator, Intent>{
                  for (final key in [
                    LogicalKeyboardKey.digit0,
                    LogicalKeyboardKey.digit1,
                    LogicalKeyboardKey.digit2,
                    LogicalKeyboardKey.digit3,
                    LogicalKeyboardKey.digit4,
                    LogicalKeyboardKey.digit5,
                    LogicalKeyboardKey.digit6,
                    LogicalKeyboardKey.digit7,
                    LogicalKeyboardKey.digit8,
                    LogicalKeyboardKey.digit9,
                    LogicalKeyboardKey.period,
                  ])
                    SingleActivator(key):
                        const DoNothingAndStopPropagationTextIntent(),
                },
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  textAlign: TextAlign.center,
                  textAlignVertical: TextAlignVertical.center,
                  keyboardType: TextInputType.number,
                  style: textStyle?.copyWith(fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'BPM',
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12.0,
                      horizontal: 8.0,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    suffixText: null,
                  ),
                  onSubmitted: (_) => _validateAndSubmit(),
                  inputFormatters: [
                    // Allow digits and decimal point for scaled BPM values
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    LengthLimitingTextInputFormatter(
                      7,
                    ), // Allow up to "999.99" or similar
                  ],
                ),
              ),
              // Position "BPM" as a separate widget to prevent it from affecting text alignment
              if (widescreen)
                Positioned(
                  right: 16,
                  child: Text(
                    "BPM",
                    style: textStyle?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onLongPressStart: (_) => _startAcceleratedChange(true),
          onLongPressEnd: (_) => _stopAcceleratedChange(performSnap: true),
          onLongPressCancel: () => _stopAcceleratedChange(performSnap: false),
          child: IconButton(
            icon: const Icon(
              Icons.add_circle_outline,
              semanticLabel: 'Increase BPM',
            ),
            iconSize: iconSize,
            splashRadius: splashRadius,
            tooltip: 'Increase BPM',
            onPressed: () => _handleIconButtonTap(true),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _longPressAccelerationTimer?.cancel();
    _tapVerificationTimer?.cancel();
    _stopAcceleratedChange(performSnap: false);
    _textController.dispose();
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }
}

// No longer need the DecimalTextInputFormatter class since we only use whole numbers now
