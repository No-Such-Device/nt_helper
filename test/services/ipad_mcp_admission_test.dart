import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/services/ipad_local_network.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Cubit extends Mock implements DistingCubit {}

class _Server extends Mock implements HttpServer {}

class _Request extends Mock implements HttpRequest {}

class _Response extends Mock implements HttpResponse {}

class _Headers extends Mock implements HttpHeaders {}

class _Connection extends Mock implements HttpConnectionInfo {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(<int>[]);
    registerFallbackValue((List<int> value, Uint8List chunk) => value);
  });
  late McpServerService service;
  late _Server server;
  late StreamController<HttpRequest> requests;
  late IpadLocalNetwork network;
  var readsFail = false;
  var binds = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService().init();
    binds = 0;
    readsFail = false;
    network = IpadLocalNetwork(
      isIpad: true,
      subnets: [
        LocalSubnet(
          InternetAddress('192.168.2.7'),
          InternetAddress('255.255.255.0'),
        ),
      ],
    );
    requests = StreamController<HttpRequest>.broadcast(sync: true);
    server = _Server();
    when(() => server.address).thenReturn(InternetAddress.anyIPv6);
    when(() => server.port).thenReturn(3847);
    when(() => server.close(force: true)).thenAnswer((_) async => server);
    when(
      () => server.listen(
        any(),
        onError: any(named: 'onError'),
        onDone: any(named: 'onDone'),
        cancelOnError: false,
      ),
    ).thenAnswer(
      (call) => requests.stream.listen(
        call.positionalArguments.first as void Function(HttpRequest),
      ),
    );
    service = McpServerService.forTesting(
      distingCubit: _Cubit(),
      readNetwork: () async {
        if (readsFail) throw StateError('Network unavailable');
        return network;
      },
      bindHttp: (address, port) async {
        expect(address, InternetAddress.anyIPv6);
        expect(port, 3847);
        binds++;
        return server;
      },
    );
  });
  tearDown(() async {
    await service.stop();
    service.dispose();
    await requests.close();
  });

  Future<void> enable() async {
    await SettingsService().setIpadMcpEnabled(true);
    await service.applySettings();
    expect(service.isRunning, isTrue);
  }

  Future<int> preflight(
    String peer, {
    String method = 'OPTIONS',
    String host = '192.168.2.7:3847',
  }) async {
    final request = _Request();
    final response = _Response();
    final connection = _Connection();
    final closed = Completer<void>();
    var status = 0;
    when(() => connection.remoteAddress).thenReturn(InternetAddress(peer));
    when(() => request.connectionInfo).thenReturn(connection);
    when(() => request.method).thenReturn(method);
    when(
      () => request.fold<List<int>>(any(), any()),
    ).thenAnswer((_) async => [123, 125]); // Empty JSON object.
    final headers = _Headers();
    when(() => headers.value(HttpHeaders.hostHeader)).thenReturn(host);
    when(() => request.headers).thenReturn(headers);
    when(() => request.uri).thenReturn(Uri.parse('/mcp'));
    when(() => request.response).thenReturn(response);
    when(() => response.headers).thenReturn(_Headers());
    when(() => response.statusCode = any()).thenAnswer((call) {
      return status = call.positionalArguments.single as int;
    });
    when(() => response.close()).thenAnswer((_) async {
      closed.complete();
    });
    requests.add(request);
    await closed.future;
    return status;
  }

  // Existing desktop transports cannot prove iPad default-off, admission or
  // lifecycle behavior. Fake server/request objects avoid real sockets/waits.
  test(
    'iPad listener stays off until Settings opt-in and stops when disabled',
    () async {
      await service.applySettings();
      expect(binds, 0);
      await enable();
      expect(binds, 1);
      await SettingsService().setIpadMcpEnabled(false);
      await service.applySettings();
      expect(service.isRunning, isFalse);
    },
  );

  test(
    'all iPad requests including preflight require a current same-subnet peer',
    () async {
      await enable();
      expect(await preflight('192.168.2.8'), HttpStatus.ok);
      expect(await preflight('192.168.3.8'), HttpStatus.forbidden);
      network = IpadLocalNetwork(
        isIpad: true,
        subnets: [
          LocalSubnet(
            InternetAddress('10.0.0.7'),
            InternetAddress('255.255.255.0'),
          ),
        ],
      );
      expect(await preflight('192.168.2.8'), HttpStatus.forbidden);
      expect(await preflight('10.0.0.8'), HttpStatus.ok);
      readsFail = true;
      expect(await preflight('10.0.0.8'), HttpStatus.forbidden);
    },
  );

  // Physical iPad initialization returned 403 despite a same-subnet peer.
  // Preflight alone never reaches the SDK's localhost-only Host protection.
  test(
    'numeric iPad LAN Host reaches SDK validation without disabling rebinding protection',
    () async {
      await enable();
      expect(
        await preflight('192.168.2.8', method: 'POST'),
        HttpStatus.notAcceptable,
      );
      expect(
        await preflight(
          '192.168.2.8',
          method: 'POST',
          host: 'attacker.example:3847',
        ),
        HttpStatus.forbidden,
      );
    },
  );

  test(
    'foreground-only iPad listener stops in background and reapplies opt-in on resume',
    () async {
      await enable();
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await service.applySettings();
      expect(service.isRunning, isFalse);
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await service.applySettings();
      expect(service.isRunning, isTrue);
      expect(binds, 2);
    },
  );

  test(
    'iPhone and missing LAN interfaces cannot start the iPad listener',
    () async {
      await SettingsService().setIpadMcpEnabled(true);
      network = const IpadLocalNetwork(isIpad: false, subnets: []);
      await service.applySettings();
      expect(binds, 0);
      expect(service.hasError, isTrue);
      network = const IpadLocalNetwork(isIpad: true, subnets: []);
      await service.applySettings();
      expect(binds, 0);
      expect(service.hasError, isTrue);
    },
  );
}
