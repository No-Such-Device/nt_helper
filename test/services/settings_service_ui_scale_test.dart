import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsService UI scale', () {
    late SettingsService settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsService();
      await settings.init();
      // Reset to a known state between tests since the service is a singleton.
      await settings.setUiScale(SettingsService.defaultUiScale);
    });

    test('default value is 1.0 when no preference stored', () async {
      SharedPreferences.setMockInitialValues({});
      await settings.init();
      expect(settings.uiScale, SettingsService.defaultUiScale);
      expect(settings.uiScale, 1.0);
    });

    test('stored value is loaded on init and reflected in notifier', () async {
      SharedPreferences.setMockInitialValues({'ui_scale': 1.2});
      await settings.init();
      expect(settings.uiScale, closeTo(1.2, 0.0001));
      expect(settings.uiScaleNotifier.value, closeTo(1.2, 0.0001));
    });

    test('setUiScale persists and updates the notifier', () async {
      final listened = <double>[];
      void listener() => listened.add(settings.uiScaleNotifier.value);
      settings.uiScaleNotifier.addListener(listener);

      await settings.setUiScale(1.3);

      expect(settings.uiScale, closeTo(1.3, 0.0001));
      expect(settings.uiScaleNotifier.value, closeTo(1.3, 0.0001));
      expect(listened, contains(closeTo(1.3, 0.0001)));

      settings.uiScaleNotifier.removeListener(listener);
    });

    test('setUiScale clamps values above the maximum', () async {
      await settings.setUiScale(10.0);
      expect(settings.uiScale, SettingsService.maxUiScale);
    });

    test('setUiScale clamps values below the minimum', () async {
      await settings.setUiScale(0.1);
      expect(settings.uiScale, SettingsService.minUiScale);
    });

    test('setUiScale rounds to one decimal place', () async {
      await settings.setUiScale(1.234567);
      expect(settings.uiScale, closeTo(1.2, 0.0001));
    });

    test('uiScale getter clamps a corrupted stored value', () async {
      SharedPreferences.setMockInitialValues({'ui_scale': 99.0});
      await settings.init();
      expect(settings.uiScale, SettingsService.maxUiScale);
    }, tags: ['regression']);

    test('zoomInUi increments by one step and clamps at maximum', () async {
      await settings.setUiScale(1.0);
      final after = await settings.zoomInUi();
      expect(after, closeTo(1.1, 0.0001));
      expect(settings.uiScale, closeTo(1.1, 0.0001));

      await settings.setUiScale(SettingsService.maxUiScale);
      final atCap = await settings.zoomInUi();
      expect(atCap, SettingsService.maxUiScale);
    });

    test('zoomOutUi decrements by one step and clamps at minimum', () async {
      await settings.setUiScale(1.0);
      final after = await settings.zoomOutUi();
      expect(after, closeTo(0.9, 0.0001));
      expect(settings.uiScale, closeTo(0.9, 0.0001));

      await settings.setUiScale(SettingsService.minUiScale);
      final atFloor = await settings.zoomOutUi();
      expect(atFloor, SettingsService.minUiScale);
    });

    test('resetUiScale restores the default scale', () async {
      await settings.setUiScale(1.3);
      final result = await settings.resetUiScale();
      expect(result, SettingsService.defaultUiScale);
      expect(settings.uiScale, SettingsService.defaultUiScale);
    });

    test('repeated zoom in then zoom out returns to original', () async {
      await settings.setUiScale(1.0);
      await settings.zoomInUi();
      await settings.zoomInUi();
      expect(settings.uiScale, closeTo(1.2, 0.0001));
      await settings.zoomOutUi();
      await settings.zoomOutUi();
      expect(settings.uiScale, closeTo(1.0, 0.0001));
    });

    test('resetToDefaults restores uiScale to default', () async {
      await settings.setUiScale(1.4);
      await settings.resetToDefaults();
      expect(settings.uiScale, SettingsService.defaultUiScale);
    });
  });
}
