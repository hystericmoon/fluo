import 'dart:convert';
import 'dart:io';

import 'package:fluo/capture/capture_controller.dart';
import 'package:fluo/capture/capture_source.dart';
import 'package:fluo/capture/folder_access.dart';
import 'package:fluo/capture/mac_capture_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'mac_capture_test.dart' show pngHeader;
import 'support/fake_source.dart';
import 'support/harness.dart';
import 'package:fluo/screens/albums.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' show TextField;

class FakeFolderAccess implements FolderAccess {
  PickedFolder? next;
  final stored = <String, OpenedFolder?>{};
  final opened = <String>[];
  int closes = 0, picks = 0;

  @override
  Future<PickedFolder?> pick() async {
    picks++;
    final n = next;
    if (n != null) stored[n.bookmark] = OpenedFolder(path: n.path);
    return n;
  }

  @override
  Future<OpenedFolder?> open(String bookmark) async {
    opened.add(bookmark);
    return stored[bookmark];
  }

  @override
  Future<void> close() async => closes++;
}

void main() {
  group('Mac folder choice', () {
    late Directory tmp;
    late Directory desktop;
    late Directory other;
    late Directory inbox;
    late FakeFolderAccess access;

    MacCaptureSource make() => MacCaptureSource(
      screenshotDir: () async => desktop,
      inboxDir: () async => inbox,
      openSystemSettings: () async {},
      folderAccess: access,
      pollInterval: const Duration(milliseconds: 40),
    );

    File choiceFile() => File(p.join(inbox.parent.path, 'capture_folder.json'));

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('fluo_folder_');
      desktop = Directory(p.join(tmp.path, 'Desktop'))..createSync();
      other = Directory(p.join(tmp.path, 'Pictures', 'Shots'))..createSync(recursive: true);
      inbox = Directory(p.join(tmp.path, 'support', 'fluo', 'inbox'));
      access = FakeFolderAccess();
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('starts on the system folder with no custom choice', () async {
      final s = make();
      expect(s.canChooseFolder, isTrue);
      await s.permission();
      expect(s.customFolder, isFalse);
      expect(s.watchedFolder, 'Desktop');
      expect(access.picks, 0);
      await s.dispose();
    });

    test('picking a folder saves the bookmark and names it', () async {
      final s = make();
      access.next = PickedFolder(path: other.path, bookmark: 'BM1');
      expect(await s.chooseFolder(), isTrue);
      expect(s.customFolder, isTrue);
      expect(s.watchedFolder, 'Shots');
      final saved = jsonDecode(choiceFile().readAsStringSync()) as Map;
      expect(saved['bookmark'], 'BM1');
      expect(saved['path'], other.path);
      await s.dispose();
    });

    test('cancelling the picker changes nothing', () async {
      final s = make();
      expect(await s.chooseFolder(), isFalse);
      expect(s.customFolder, isFalse);
      expect(choiceFile().existsSync(), isFalse);
      await s.dispose();
    });

    test('captures from the picked folder, not the Desktop', () async {
      final s = make();
      access.next = PickedFolder(path: other.path, bookmark: 'BM1');
      await s.chooseFolder();
      await s.start();
      File(p.join(desktop.path, 'Screenshot 2026-11-10 at 10.00.00.png'))
          .writeAsBytesSync(pngHeader(10, 20));
      File(p.join(other.path, 'Screenshot 2026-11-10 at 10.00.01.png'))
          .writeAsBytesSync(pngHeader(30, 40));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final got = await s.drain();
      expect(got, hasLength(1));
      expect(got.single.width, 30);
      await s.stop();
      await s.dispose();
    });

    test('a restart reopens the saved bookmark', () async {
      final first = make();
      access.next = PickedFolder(path: other.path, bookmark: 'BM1');
      await first.chooseFolder();
      await first.dispose();

      access.opened.clear();
      final second = make();
      expect(await second.permission(), CapturePermission.granted);
      expect(access.opened, ['BM1']);
      expect(second.customFolder, isTrue);
      expect(second.watchedFolder, 'Shots');
      await second.dispose();
    });

    test('a stale bookmark is replaced with the fresh one', () async {
      choiceFile().createSync(recursive: true);
      choiceFile().writeAsStringSync(jsonEncode({'path': other.path, 'bookmark': 'OLD'}));
      access.stored['OLD'] = OpenedFolder(path: other.path, bookmark: 'NEW');
      final s = make();
      await s.permission();
      expect(jsonDecode(choiceFile().readAsStringSync())['bookmark'], 'NEW');
      await s.dispose();
    });

    test('a lost folder asks for a pick instead of silently using the Desktop', () async {
      choiceFile().createSync(recursive: true);
      choiceFile().writeAsStringSync(jsonEncode({'path': other.path, 'bookmark': 'GONE'}));
      final s = make();
      expect(await s.permission(), CapturePermission.denied);
      expect(s.watchedFolder, isNull);
      await expectLater(s.start(), throwsA(isA<FileSystemException>()));
      // "Allow folder access" opens the picker; picking fixes it.
      access.next = PickedFolder(path: other.path, bookmark: 'BM2');
      expect(await s.requestPermission(), CapturePermission.granted);
      expect(s.watchedFolder, 'Shots');
      await s.dispose();
    });

    test('a corrupt choice file is treated as a lost folder, not a crash', () async {
      choiceFile().createSync(recursive: true);
      choiceFile().writeAsStringSync('not json');
      final s = make();
      expect(await s.permission(), CapturePermission.denied);
      await s.dispose();
    });

    test('useDefaultFolder forgets the choice', () async {
      final s = make();
      access.next = PickedFolder(path: other.path, bookmark: 'BM1');
      await s.chooseFolder();
      await s.useDefaultFolder();
      expect(s.customFolder, isFalse);
      expect(choiceFile().existsSync(), isFalse);
      expect(access.closes, 1);
      await s.permission();
      expect(s.watchedFolder, 'Desktop');
      await s.dispose();
    });

    test('an unreadable default folder asks for a pick, a picked one needs Settings', () async {
      if (Platform.isWindows) return;
      final locked = Directory(p.join(tmp.path, 'Locked'))..createSync();
      Process.runSync('chmod', ['000', locked.path]);
      addTearDown(() => Process.runSync('chmod', ['755', locked.path]));
      if (File(locked.path).statSync().mode & 0x1ff != 0) return; // running as root
      final s = MacCaptureSource(
        screenshotDir: () async => locked,
        inboxDir: () async => inbox,
        folderAccess: access,
      );
      expect(await s.permission(), CapturePermission.denied);
      access.next = PickedFolder(path: locked.path, bookmark: 'L');
      expect(await s.requestPermission(), CapturePermission.permanentlyDenied);
      await s.dispose();
    });
  });

  group('dropped files', () {
    late Directory tmp;
    late Directory shared;
    late MacCaptureSource src;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('fluo_drop_');
      shared = Directory(p.join(tmp.path, 'shared'));
      src = MacCaptureSource(
        screenshotDir: () async => Directory(p.join(tmp.path, 'Desktop')),
        inboxDir: () async => Directory(p.join(tmp.path, 'inbox')),
        sharedDir: () async => shared,
        folderAccess: FakeFolderAccess(),
      );
    });
    tearDown(() async {
      await src.dispose();
      tmp.deleteSync(recursive: true);
    });

    File img(String name, [List<int>? bytes]) => File(p.join(tmp.path, name))
      ..writeAsBytesSync(bytes ?? pngHeader(50, 80));

    test('copies images, skips other files, and waits for an album', () async {
      expect(src.canImportFiles, isTrue);
      final fired = <void>[];
      src.sharedIn.listen(fired.add);
      final n = await src.importFiles([
        img('a.png').path,
        img('b.JPG').path,
        File(p.join(tmp.path, 'notes.txt')).path,
        p.join(tmp.path, 'missing.png'),
        img('doc.pdf').path,
      ]);
      expect(n, 2);
      await Future<void>.delayed(Duration.zero);
      expect(fired, hasLength(1));
      final got = await src.drainShared();
      expect(got, hasLength(2));
      expect(got.any((s) => s.width == 50 && s.height == 80), isTrue);
      // Dropped files are copies: the originals are untouched, and the
      // session inbox is separate.
      expect(File(p.join(tmp.path, 'a.png')).existsSync(), isTrue);
      expect(await src.drain(), isEmpty);
      await src.ackShared([for (final s in got) s.path]);
      expect(await src.drainShared(), isEmpty);
    });

    test('dropping the same file twice adds it once', () async {
      final f = img('a.png');
      await src.importFiles([f.path]);
      await src.importFiles([f.path]);
      expect(await src.drainShared(), hasLength(1));
    });

    test('nothing importable means no event', () async {
      var fired = 0;
      src.sharedIn.listen((_) => fired++);
      expect(await src.importFiles([img('x.txt').path]), 0);
      await Future<void>.delayed(Duration.zero);
      expect(fired, 0);
      expect(await src.drainShared(), isEmpty);
    });

    test('the phone and no-capture sources cannot import', () async {
      expect(NoCaptureSource().canImportFiles, isFalse);
      expect(await NoCaptureSource().importFiles(['a.png']), 0);
      expect(AndroidCaptureSource().canImportFiles, isFalse);
    });
  });

  group('MacFolderAccess channel', () {
    const ch = MethodChannel('test/folder');
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, null));

    void mock(Future<Object?> Function(MethodCall) h) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ch, h);

    test('maps pick, open and errors', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final a = MacFolderAccess(channel: ch);
      mock((c) async => switch (c.method) {
        'pick' => {'path': '/x/Shots', 'bookmark': 'B'},
        'open' => {'path': '/x/Shots', 'stale': true, 'bookmark': 'B2'},
        _ => null,
      });
      final picked = await a.pick();
      expect((picked!.path, picked.bookmark), ('/x/Shots', 'B'));
      final opened = await a.open('B');
      expect((opened!.path, opened.bookmark), ('/x/Shots', 'B2'));

      mock((c) async => null); // cancelled
      expect(await a.pick(), isNull);

      mock((c) async => throw PlatformException(code: 'bookmark'));
      expect(await a.open('B'), isNull);
      expect(await a.pick(), isNull);
    });
  });

  group('controller drop', () {
    testWidgets('a drop bumps sharedArrived only when files were taken', (t) async {
      final repo = memRepo();
      final src = FakeSource()..canImportFiles = true;
      final c = CaptureController(repo, src);
      addTearDown(c.dispose);
      expect(c.canImportFiles, isTrue);
      expect(await c.importFiles(['a.png', 'b.png']), 2);
      expect(c.sharedArrived.value, 1);
      expect(src.imported, ['a.png', 'b.png']);
      expect(await c.importFiles([]), 0);
      expect(c.sharedArrived.value, 1);
    });
  });

  group('session card folder buttons', () {
    testWidgets('the Mac card can choose and reset the folder; the phone card has no buttons', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final mac = FakeSource(copy: CaptureCopy.mac, watchedFolder: 'Desktop')
        ..canChooseFolder = true;
      await tester.pumpWidget(host(const AlbumsScreen(), source: mac));
      await tester.tap(find.text('New album'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Checkout');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Choose folder'), findsOneWidget);
      expect(find.text('Use default'), findsNothing);
      await tester.tap(find.text('Choose folder'));
      await tester.pumpAndSettle();
      expect(mac.folderChoices, 1);
      expect(mac.starts, greaterThan(1), reason: 'watch restarted on the new folder');
      expect(find.textContaining('Watching Shots.'), findsOneWidget);
      expect(find.text('Change folder'), findsOneWidget);

      await tester.tap(find.text('Use default'));
      await tester.pumpAndSettle();
      expect(mac.folderResets, 1);
      expect(find.textContaining('Watching Desktop.'), findsOneWidget);
    });

    testWidgets('a cancelled pick leaves the watch alone', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final mac = FakeSource(copy: CaptureCopy.mac, watchedFolder: 'Desktop')
        ..canChooseFolder = true
        ..pickResult = false;
      await tester.pumpWidget(host(const AlbumsScreen(), source: mac));
      await tester.tap(find.text('New album'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Checkout');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      final starts = mac.starts;
      await tester.tap(find.text('Choose folder'));
      await tester.pumpAndSettle();
      expect(mac.starts, starts);
      expect(find.textContaining('Watching Desktop.'), findsOneWidget);
    });

    testWidgets('Android shows no folder buttons', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const AlbumsScreen(), source: FakeSource()));
      await tester.tap(find.text('New album'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Checkout');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text('Choose folder'), findsNothing);
      expect(find.text('Change folder'), findsNothing);
    });
  });
}
