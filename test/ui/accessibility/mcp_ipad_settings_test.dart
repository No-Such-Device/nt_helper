import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/services/mcp_lan_context.dart';
import 'package:nt_helper/services/mcp_lan_policy.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/widgets/mcp_ipad_settings.dart';
import 'package:nt_helper/ui/widgets/mcp_status_indicator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Use the existing preferences package's platform seam to fail the actual save.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _Cubit extends Mock implements DistingCubit {}

class _Context implements McpLanContext {
  String idiom = 'pad';
  Completer<McpLanSnapshot>? gate;
  bool fail = false;
  @override
  Future<McpLanSnapshot> snapshot() async {
    if (fail) throw StateError('synthetic-private-context');
    if (gate != null) return gate!.future;
    return McpLanSnapshot.decode({
      'version': 1,
      'idiom': idiom,
      'pathGeneration': 1,
      'pathCurrent': true,
      'interfaces': [
        {
          'index': 7,
          'name': 'physical-lan',
          'type': 'wifi',
          'flags': 0x41,
          'addresses': [
            {
              'family': 'ipv4',
              'bytes': [192, 168, 2, 1],
              'mask': [255, 255, 254, 0],
              'prefix': 23,
              'scopeId': 0,
            },
          ],
        },
      ],
    });
  }
}

class _Listener extends Stream<Socket> implements ServerSocket {
  final incoming = StreamController<Socket>();
  @override
  InternetAddress get address => InternetAddress('192.168.2.1');
  @override
  int get port => 3847;
  @override
  Future<ServerSocket> close() async {
    unawaited(incoming.close());
    return this;
  }

  @override
  StreamSubscription<Socket> listen(
    void Function(Socket)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => incoming.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.empty();
  bool fail = false;
  Completer<bool>? gate;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (gate != null) return gate!.future;
    if (fail) throw StateError('synthetic-private-save');
    return super.setValue(valueType, key, value);
  }
}

const _receipt =
    '{"version":1,"consentVersion":1,"interfaceIndex":7,"address":"192.168.2.1","peers":["192.168.3.2"]}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Context native;
  late McpServerService service;
  late _Store store;
  late int binds;
  late bool rngFails;
  late int randomCalls;
  final copies = <String>[];
  final announcements = <Object?>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    await SettingsService().init();
    native = _Context();
    binds = 0;
    randomCalls = 0;
    rngFails = false;
    copies.clear();
    announcements.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
          message,
        ) async {
          announcements.add(message);
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copies.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  void createService({bool supported = true}) {
    service = McpServerService.forTesting(
      distingCubit: _Cubit(),
      context: native,
      ipadSupported: supported,
      randomBytes: () {
        if (rngFails) throw StateError('synthetic-private-rng');
        return List.filled(32, ++randomCalls);
      },
      bindSocket: (address, port, {required shared, required v6Only}) async {
        binds++;
        return _Listener();
      },
    );
  }

  tearDown(() {
    service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          SystemChannels.accessibility,
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> mount(WidgetTester tester, {bool dialog = false}) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: dialog
              ? Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showDialog<bool>(
                      context: context,
                      builder: (_) => SettingsDialog(mcpService: service),
                    ),
                    child: const Text('Open Settings'),
                  ),
                )
              : SingleChildScrollView(
                  child: SizedBox(
                    width: 420,
                    child: McpIpadSettingsPanel(service: service),
                  ),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (dialog) {
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> configure(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('192.168.2.1/23 (physical-lan)').last);
    await tester.pumpAndSettle();
    final peerField = find.descendant(
      of: find.byType(McpIpadSettingsPanel),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(peerField);
    await tester.enterText(peerField, '192.168.3.2');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
  }

  // AC-001: service-only enable fixtures cannot prove the actual Settings
  // command, canceled staging, unrelated Save or restored/restarted UI path.
  testWidgets(
    'AC-001 Settings alone grants consent; restore cancel and unrelated Save never bind',
    (tester) async {
      createService();
      for (final raw in [null, _receipt, true, '{"version":99}', 'malformed']) {
        SharedPreferences.setMockInitialValues({
          'mcp_enabled': true,
          'mcp_remote_connections': true,
          'mcp_ipad_configuration': ?raw,
        });
        await SettingsService().init();
        await mount(tester, dialog: true);
        expect(service.ipadState, McpIpadState.off);
        expect(binds, 0);
        await tap(tester, 'Cancel');
        await mount(tester, dialog: true);
        await tap(tester, 'Save');
        expect(binds, 0);
        await tester.pumpWidget(const SizedBox());
      }
      await mount(tester, dialog: true);
      // A valid restored selection is shown but does not enable until this action.
      await configure(tester);
      expect(binds, 0);
      await tap(tester, 'Enable / retry in Settings');
      expect(service.isRunning, isTrue);
      expect(binds, 1);
      expect(SettingsService().mcpIpadConfiguration!.peers, ['192.168.3.2']);
      await tester.enterText(
        find.descendant(
          of: find.byType(McpIpadSettingsPanel),
          matching: find.byType(TextField),
        ),
        '192.168.3.3',
      );
      expect(service.ipadToken, isNull);
      await tester.pumpAndSettle();
      await tap(tester, 'Cancel');
      await tester.pumpWidget(const SizedBox());
      service.dispose();
      createService(); // A new process/runtime cannot inherit the saved receipt.
      await SettingsService().init();
      await mount(tester);
      expect(service.ipadState, McpIpadState.off);
      expect(binds, 1);
    },
  );

  // AC-001/007: transport persistence callbacks do not exercise the real
  // preferences failure, Settings editing, UI clipboard or hidden credentials.
  testWidgets(
    'AC-001 AC-007 failed save rotation and edits revoke; copying stays deliberate and separate',
    (tester) async {
      createService();
      await mount(tester);
      await configure(tester);
      store.fail = true;
      await tap(tester, 'Enable / retry in Settings');
      expect(service.ipadState, McpIpadState.failed);
      expect(binds, 0);
      expect(service.ipadToken, isNull);
      expect(copies, isEmpty);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enable / retry in Settings'),
            )
            .onPressed,
        isNotNull,
        reason:
            'ack=${tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value}, state=${service.ipadState}',
      );
      store.fail = false;
      await tap(tester, 'Enable / retry in Settings');
      expect(
        service.ipadState,
        McpIpadState.running,
        reason: service.ipadReason,
      );
      final token = service.ipadToken!;
      expect(token.length, 43);
      expect(find.text(token), findsNothing);
      expect(copies, isEmpty);
      await tap(tester, 'Copy endpoint');
      expect(copies, ['http://192.168.2.1:3847/mcp']);
      await tap(tester, 'Copy token');
      expect(copies, ['http://192.168.2.1:3847/mcp', token]);
      await tap(tester, 'Reveal token');
      expect(find.text(token), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonEncode({for (final k in prefs.getKeys()) k: prefs.get(k)}),
        isNot(contains(token)),
      );
      rngFails = true;
      await tap(tester, 'Regenerate token');
      expect(service.ipadState, McpIpadState.failed);
      expect(service.ipadToken, isNull);
      expect(find.text(token), findsNothing);
      expect(binds, 1);
      rngFails = false;
      await tap(tester, 'Enable / retry in Settings');
      expect(service.ipadToken, isNot(token));
      await tester.enterText(
        find.byType(TextField),
        'invalid-user-pasted-secret',
      );
      expect(service.ipadToken, isNull); // before any async cleanup/save
      await tester.pumpAndSettle();
      expect(service.isRunning, isFalse);
      store.fail = true;
      await tap(tester, 'Disable');
      expect(service.ipadState, McpIpadState.off);
      expect(copies.length, 2);
      expect(announcements.join(), isNot(contains(token)));
      expect(service.ipadReason, isNot(contains('synthetic-private')));
    },
  );

  // AC-009: earlier generic semantics tests do not observe this profile's
  // async consent/state/error/peer slots or keyboard traversal.
  testWidgets(
    'AC-009 async Settings geometry semantics focus and announcements remain stable',
    (tester) async {
      createService();
      final handle = tester.ensureSemantics();
      try {
        await mount(tester);
        await configure(tester);
        final panel = find.byType(McpIpadSettingsPanel);
        final state = find.byKey(const ValueKey('ipad-mcp-state'));
        final validation = find.byKey(const ValueKey('ipad-mcp-validation'));
        Rect relative(Finder f) =>
            tester.getRect(f).shift(-tester.getTopLeft(panel));
        final stateRect = relative(state);
        final validationRect = relative(validation);
        final buttonRect = relative(find.text('Disable'));
        void stable() {
          expect(relative(state), stateRect);
          expect(relative(validation), validationRect);
          expect(relative(find.text('Disable')), buttonRect);
        }

        store.gate = Completer<bool>();
        await tap(tester, 'Enable / retry in Settings');
        expect(service.ipadState, McpIpadState.starting);
        stable();
        await tester.ensureVisible(state);
        await tester.pump();
        expect(
          tester
              .getSemantics(state)
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        expect(tester.getSemantics(state).label, contains('STARTING'));
        store.gate!.complete(false);
        await tester.pumpAndSettle();
        stable();
        expect(tester.getSemantics(state).label, contains('FAILED'));
        store.gate = null;
        await tap(tester, 'Enable / retry in Settings');
        expect(service.isRunning, isTrue);
        stable();
        expect(tester.getSemantics(state).label, contains('RUNNING'));
        unawaited(service.ipadLifecycleChanged('inactive'));
        await tester.pumpAndSettle();
        stable();
        expect(tester.getSemantics(state).label, contains('PAUSED'));
        unawaited(service.ipadLifecycleChanged('resumed'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'not-a-peer');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        await tap(tester, 'Enable / retry in Settings');
        stable();
        expect(
          tester.getSemantics(validation).label,
          contains('exact numeric peers'),
        );
        expect(
          tester
              .getSemantics(validation)
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        await tester.ensureVisible(find.text('iPad LAN MCP'));
        await tester.pump();
        expect(
          tester
              .getSemantics(find.text('iPad LAN MCP'))
              .getSemanticsData()
              .flagsCollection
              .isHeader,
          isTrue,
        );
        final peers = find.byType(TextField);
        await tester.ensureVisible(peers);
        await tester.tap(peers);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          isNot(contains('EditableText')),
        );
        expect(find.textContaining('On-path observers'), findsOneWidget);
        expect(find.textContaining('OS Local Network grant'), findsOneWidget);
        final spoken = announcements.join();
        for (final state in ['starting', 'failed', 'running', 'paused']) {
          expect(spoken, contains('iPad LAN MCP: $state'));
        }
        expect(spoken, contains('exact numeric peers'));
      } finally {
        handle.dispose();
      }
    },
  );

  // AC-001/009: width-based desktop fixtures cannot establish compact native
  // identity, unsupported identity, or that status taps cannot grant authority.
  testWidgets(
    'AC-001 AC-009 native eligibility ignores width and status only opens Settings',
    (tester) async {
      createService(supported: false);
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester);
      expect(find.text('iPad LAN MCP'), findsNothing);
      expect(binds, 0);
      service.dispose();
      createService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider.value(
              value: service,
              child: const McpStatusIndicator(),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsOneWidget);
      expect(find.text('iPad LAN MCP'), findsOneWidget);
      expect(binds, 0);
    },
  );
}
