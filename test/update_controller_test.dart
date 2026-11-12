import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/settings/app_settings.dart';
import 'package:fluo/update/update_controller.dart';
import 'package:fluo/update/update_source.dart';

import 'support/fake_update.dart';
import 'support/harness.dart';

void main() {
  late AppSettings settings;
  late FakeUpdateSource src;
  late FakeNetwork net;
  late UpdateController c;

  setUp(() {
    settings = AppSettings(memRepo());
    src = FakeUpdateSource();
    net = FakeNetwork();
    c = UpdateController(settings: settings, source: src, network: net, appInfo: const FakeAppInfo());
  });

  tearDown(() => c.dispose());

  test('starts idle and learns the version', () async {
    expect(c.state, UpdateState.idle);
    await Future<void>.delayed(Duration.zero);
    expect(c.info.toString(), '0.1.0 (1)');
  });

  group('checking by hand', () {
    test('up to date', () async {
      await c.checkNow();
      expect(c.state, UpdateState.upToDate);
    });

    test('an update is available', () async {
      src.available = true;
      await c.checkNow();
      expect(c.state, UpdateState.available);
      expect(src.downloads, 0, reason: 'a manual check does not download by itself');
    });

    test('a copy not installed from Play is "unavailable", not an error', () async {
      src.unsupported = true;
      await c.checkNow();
      expect(c.state, UpdateState.unavailable);
    });

    test('a copy that cannot update is remembered, so the controls stay hidden next launch', () async {
      expect(c.canUpdate, isTrue, reason: 'assumed until a check says otherwise');
      src.unsupported = true;
      await c.checkNow();
      expect(c.canUpdate, isFalse);
      expect(settings.updatesUnsupported, isTrue);
    });

    test('a later successful check clears that', () async {
      settings.setUpdatesUnsupported(true);
      src.unsupported = false;
      await c.checkNow();
      expect(settings.updatesUnsupported, isFalse);
      expect(c.canUpdate, isTrue);
    });

    test('a build with no update source (desktop) never offers updates', () async {
      final desktop = UpdateController(
          settings: settings, source: const NoUpdateSource(), network: net, appInfo: const FakeAppInfo());
      addTearDown(desktop.dispose);
      expect(desktop.canUpdate, isFalse);
    });

    test('any other failure is "failed" and can be retried', () async {
      src.checkError = Exception('boom');
      await c.checkNow();
      expect(c.state, UpdateState.failed);
      src.checkError = null;
      await c.checkNow();
      expect(c.state, UpdateState.upToDate);
    });

    test('it is checking in between, and a second tap meanwhile does nothing', () async {
      final states = <UpdateState>[];
      c.addListener(() => states.add(c.state));
      final first = c.checkNow();
      final second = c.checkNow();
      await Future.wait([first, second]);
      expect(states, [UpdateState.checking, UpdateState.upToDate]);
      expect(src.checks, 1);
    });

    test('it ignores the Wi-Fi setting: the person asked', () async {
      net.unmetered = false;
      settings.setWifiOnly(true);
      await c.checkNow();
      expect(src.checks, 1);
      expect(net.asked, 0);
    });
  });

  group('downloading and installing', () {
    Future<void> available() async {
      src.available = true;
      await c.checkNow();
    }

    test('download starts only when an update is available', () async {
      await c.download();
      expect(src.downloads, 0);
      await available();
      await c.download();
      expect(src.downloads, 1);
      expect(c.state, UpdateState.downloading);
    });

    test('declining the Play dialog returns to "available"', () async {
      src.startAccepted = false;
      await available();
      await c.download();
      expect(c.state, UpdateState.available);
    });

    test('progress from Play moves it to ready, and install is allowed only then', () async {
      await available();
      await c.download();
      await c.install();
      expect(src.installs, 0, reason: 'not downloaded yet');
      src.emit(UpdatePhase.downloading);
      await Future<void>.delayed(Duration.zero);
      expect(c.state, UpdateState.downloading);
      src.emit(UpdatePhase.downloaded);
      await Future<void>.delayed(Duration.zero);
      expect(c.state, UpdateState.ready);
      await c.install();
      expect(src.installs, 1);
    });

    test('a failed download is reported, and a late "downloading" does not undo "ready"', () async {
      await available();
      await c.download();
      src.emit(UpdatePhase.failed);
      await Future<void>.delayed(Duration.zero);
      expect(c.state, UpdateState.failed);

      src.emit(UpdatePhase.downloaded);
      await Future<void>.delayed(Duration.zero);
      src.emit(UpdatePhase.downloading);
      await Future<void>.delayed(Duration.zero);
      expect(c.state, UpdateState.ready);
    });
  });

  group('auto-update on launch', () {
    final now = DateTime(2026, 11, 9, 12);

    test('off: does nothing at all', () async {
      settings.setAutoUpdate(false);
      await c.autoCheck(now: now);
      expect((src.checks, net.asked), (0, 0));
    });

    test('Wi-Fi only on a metered connection: skips, and does not count it as a check', () async {
      net.unmetered = false;
      await c.autoCheck(now: now);
      expect(src.checks, 0);
      expect(settings.lastUpdateCheck, isNull, reason: 'so the next launch tries again');
    });

    test('Wi-Fi only on an unmetered connection: checks, records it, downloads an available update', () async {
      src.available = true;
      await c.autoCheck(now: now);
      expect(src.checks, 1);
      expect(src.downloads, 1);
      expect(settings.lastUpdateCheck, now);
      expect(c.state, UpdateState.downloading);
    });

    test('up to date: checks, records it, downloads nothing', () async {
      await c.autoCheck(now: now);
      expect((src.checks, src.downloads), (1, 0));
      expect(c.state, UpdateState.upToDate);
    });

    test('Wi-Fi only off: checks even on mobile data, without asking about the network', () async {
      net.unmetered = false;
      settings.setWifiOnly(false);
      await c.autoCheck(now: now);
      expect(src.checks, 1);
      expect(net.asked, 0);
    });

    test('not more than once every 12 hours', () async {
      await c.autoCheck(now: now);
      await c.autoCheck(now: now.add(const Duration(hours: 11, minutes: 59)));
      expect(src.checks, 1);
      await c.autoCheck(now: now.add(const Duration(hours: 12)));
      expect(src.checks, 2);
    });

    test('a copy not installed from Play ends quietly as "unavailable"', () async {
      src.unsupported = true;
      await c.autoCheck(now: now);
      expect(c.state, UpdateState.unavailable);
      expect(src.downloads, 0);
    });

    test('a failing check does not crash the launch and is recorded', () async {
      src.checkError = Exception('offline');
      await c.autoCheck(now: now);
      expect(c.state, UpdateState.failed);
      expect(settings.lastUpdateCheck, now);
    });
  });

  test('the Android sources are not used off Android', () async {
    await expectLater(const NoUpdateSource().checkAvailable(), throwsA(isA<UpdateUnsupported>()));
    expect(await const NoNetworkInfo().isUnmetered(), isTrue);
    expect(const AppInfo('1.2.3', '45').toString(), '1.2.3 (45)');
    expect(const AppInfo('1.2.3', '').toString(), '1.2.3');
  });
}
