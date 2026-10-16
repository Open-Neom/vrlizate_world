import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vrlizate_world/vrlizate_world_io.dart';

void main() {
  late Directory directory;
  late DateTime now;

  VrRegionDiskCache cache({
    int maxBytes = 8192,
    int maxEntries = 8,
    int? maxEntryBytes,
    Duration idleTtl = const Duration(hours: 1),
  }) => VrRegionDiskCache(
    directoryPath: directory.path,
    maxBytes: maxBytes,
    maxEntries: maxEntries,
    maxEntryBytes: maxEntryBytes,
    idleTtl: idleTtl,
    clock: () => now,
  );

  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  Future<List<File>> managedFiles() async =>
      (await Directory(
            '${directory.path}/vrlizate-regions-v1',
          ).list(followLinks: false).toList())
          .whereType<File>()
          .where((file) => file.path.endsWith('.vrregion'))
          .toList();

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vr-region-cache-');
    now = DateTime.utc(2026, 10, 8, 12);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'encoded region survives reopening with its complete identity',
    () async {
      const key = 'earth|public-01|origin:19.4,-99.1|tile:4,5|revision:2';
      final original = cache();
      expect(
        await original.write(key, bytes('encoded world entities')),
        isTrue,
      );
      now = now.add(const Duration(minutes: 10));
      final reopened = cache();
      expect(await reopened.read(key), bytes('encoded world entities'));
      expect(await reopened.read('$key-other-origin'), isNull);
      final stats = await reopened.stats();
      expect(stats.entryCount, 1);
      expect(
        stats.totalBytes,
        greaterThan(bytes('encoded world entities').length),
      );
      expect(stats.hits, 1);
      expect(stats.misses, 1);
    },
  );

  test(
    'count budget evicts least recently visited region across reopen',
    () async {
      final original = cache(maxEntries: 2);
      await original.write('a', bytes('a'));
      now = now.add(const Duration(seconds: 1));
      await original.write('b', bytes('b'));
      now = now.add(const Duration(seconds: 1));
      await original.read('a');
      now = now.add(const Duration(seconds: 1));
      final reopened = cache(maxEntries: 2);
      await reopened.write('c', bytes('c'));
      expect(await reopened.read('b'), isNull);
      expect(await reopened.read('a'), bytes('a'));
      expect(await reopened.read('c'), bytes('c'));
      expect((await reopened.stats()).entryCount, 2);
    },
  );

  test(
    'byte budget includes envelopes and survives smaller reopened limit',
    () async {
      final original = cache();
      await original.write('a', Uint8List(100));
      now = now.add(const Duration(seconds: 1));
      await original.write('b', Uint8List(100));
      final total = (await original.stats()).totalBytes;
      final smaller = cache(maxBytes: total - 1);
      final stats = await smaller.prune();
      expect(stats.entryCount, 1);
      expect(stats.totalBytes, lessThanOrEqualTo(total - 1));
      expect(await smaller.read('a'), isNull);
      expect(await smaller.read('b'), Uint8List(100));
    },
  );

  test('idle TTL refreshes on visits and expires after reopening', () async {
    final original = cache();
    await original.write('a', bytes('a'));
    now = now.add(const Duration(minutes: 50));
    expect(await original.read('a'), bytes('a'));
    now = now.add(const Duration(minutes: 50));
    expect((await cache().stats()).entryCount, 1);
    now = now.add(const Duration(minutes: 10));
    final reopened = cache();
    expect(await reopened.read('a'), isNull);
    expect((await reopened.stats()).entryCount, 0);
    expect(await managedFiles(), isEmpty);
  });

  test(
    'payload corruption is a miss and removes only its managed entry',
    () async {
      final original = cache();
      await original.write('a', bytes('content'));
      final file = (await managedFiles()).single;
      final stored = await file.readAsBytes();
      stored[stored.length - 1] ^= 0xff;
      await file.writeAsBytes(stored);
      await file.setLastModified(now);
      expect(await original.read('a'), isNull);
      expect(await file.exists(), isFalse);
      expect(await original.write('a', bytes('redownloaded')), isTrue);
      expect(await original.read('a'), bytes('redownloaded'));
    },
  );

  test(
    'truncated or oversized metadata is rejected before payload allocation',
    () async {
      final original = cache();
      await original.write('a', bytes('a'));
      var file = (await managedFiles()).single;
      await file.writeAsBytes([1, 2, 3]);
      await file.setLastModified(now);
      expect(await original.read('a'), isNull);
      await original.write('a', bytes('a'));
      file = (await managedFiles()).single;
      final stored = await file.readAsBytes();
      ByteData.sublistView(stored).setUint32(8, 0xffffffff);
      await file.writeAsBytes(stored);
      await file.setLastModified(now);
      expect(await original.read('a'), isNull);
    },
  );

  test(
    'per-entry limit bounds both writes and reads of preexisting files',
    () async {
      expect(await cache(maxEntryBytes: 8).write('a', Uint8List(9)), isFalse);
      await cache().write('a', Uint8List(100));
      expect(await cache(maxEntryBytes: 8).read('a'), isNull);
      expect(await managedFiles(), isEmpty);
      expect(await cache(maxBytes: 1).write('a', Uint8List(0)), isFalse);
    },
  );

  test(
    'opaque path-like keys cannot escape and unrelated files survive pruning',
    () async {
      final outside = File('${directory.path}/keep.txt');
      await outside.writeAsString('saved session context');
      final original = cache();
      const key = '../../keep.txt/../somewhere\\else\u0000|revision:5';
      expect(await original.write(key, bytes('region')), isTrue);
      expect(await original.read(key), bytes('region'));
      final unmanaged = File(
        '${directory.path}/vrlizate-regions-v1/user-save.json',
      );
      await unmanaged.writeAsString('keep this too');
      now = now.add(const Duration(hours: 2));
      await original.prune();
      expect(await outside.readAsString(), 'saved session context');
      expect(await unmanaged.readAsString(), 'keep this too');
      expect(await managedFiles(), isEmpty);
    },
  );

  test(
    'managed-looking symlinks are not followed, replaced or deleted',
    () async {
      final original = cache();
      await original.write('a', bytes('a'));
      final entry = (await managedFiles()).single;
      await entry.delete();
      final target = File('${directory.path}/outside-region-data');
      await target.writeAsString('preserve target');
      final link = await Link(entry.path).create(target.path);
      expect(await original.read('a'), isNull);
      expect(await original.write('a', bytes('replacement')), isFalse);
      await original.prune();
      expect(await link.exists(), isTrue);
      expect(await target.readAsString(), 'preserve target');
    },
    skip: Platform.isWindows
        ? 'Symlink creation needs Windows privileges.'
        : false,
  );

  test(
    'cache namespace symlink refuses storage without touching target',
    () async {
      final target = await Directory('${directory.path}/other-data').create();
      await Link('${directory.path}/vrlizate-regions-v1').create(target.path);
      expect(await cache().write('a', bytes('a')), isFalse);
      expect(await cache().read('a'), isNull);
      expect(await target.list().toList(), isEmpty);
    },
    skip: Platform.isWindows
        ? 'Symlink creation needs Windows privileges.'
        : false,
  );

  test(
    'queued writes own their input and committed overwrites stay readable',
    () async {
      final original = cache();
      final input = bytes('first');
      final write = original.write('a', input);
      input[0] = 0;
      expect(await write, isTrue);
      expect(await original.read('a'), bytes('first'));
      await Future.wait([
        original.write('a', bytes('second')),
        original.write('a', bytes('third')),
        original.write('b', bytes('independent')),
      ]);
      expect(await original.read('a'), bytes('third'));
      expect(await original.read('b'), bytes('independent'));
    },
  );

  test(
    'invalid keys and policy values fail without filesystem mutation',
    () async {
      expect(() => cache().read(''), throwsArgumentError);
      expect(
        () => cache().write('x' * 4097, Uint8List(0)),
        throwsArgumentError,
      );
      expect(() => cache(maxBytes: 0), throwsArgumentError);
      expect(() => cache(maxEntries: 0), throwsArgumentError);
      expect(() => cache(idleTtl: Duration.zero), throwsArgumentError);
      expect(() => cache(maxBytes: 8, maxEntryBytes: 9), throwsArgumentError);
      expect(await directory.list().toList(), isEmpty);
    },
  );
}
