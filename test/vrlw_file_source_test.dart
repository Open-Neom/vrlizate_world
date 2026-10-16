import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vrlizate_world/src/bundles/vrlw_byte_source.dart';
import 'package:vrlizate_world/src/bundles/vrlw_file_source.dart';

void main() {
  test('memory source isolates input and returned range buffers', () async {
    final original = Uint8List.fromList([1, 2, 3, 4]);
    final source = VrlwMemorySource(original);
    original[1] = 99;
    expect(source.length, 4);
    final bytes = await source.readRange(1, 2);
    expect(bytes, [2, 3]);
    bytes[0] = 77;
    expect(await source.readRange(1, 2), [2, 3]);
    await source.close();
    await source.close();
    await expectLater(source.readRange(0, 1), throwsStateError);
  });

  test('memory rejects invalid and excessive ranges', () async {
    final source = VrlwMemorySource(Uint8List(10));
    addTearDown(source.close);
    for (final range in [
      (-1, 1),
      (0, 0),
      (0, -1),
      (9, 2),
      (10, 1),
      (0, VrlwByteSource.maxReadLength + 1),
    ]) {
      await expectLater(source.readRange(range.$1, range.$2), throwsRangeError);
    }
  });

  group('native source', () {
    late Directory temporary;
    late File file;
    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('vrlw-source-');
      file = File('${temporary.path}/place.vrlw');
      await file.writeAsBytes(List.generate(256, (index) => index));
    });
    tearDown(() async => temporary.delete(recursive: true));

    test(
      'reads only requested ranges and serializes simultaneous seeks',
      () async {
        final source = await VrlwFileSource.open(file.path);
        addTearDown(source.close);
        expect(source.length, 256);
        final results = await Future.wait([
          for (var index = 0; index < 32; index++)
            source.readRange(index * 8, 8),
        ]);
        for (var index = 0; index < results.length; index++) {
          expect(results[index], List.generate(8, (n) => index * 8 + n));
        }
      },
    );

    test('one invalid range does not break the read queue', () async {
      final source = await VrlwFileSource.open(file.path);
      addTearDown(source.close);
      await expectLater(source.readRange(256, 1), throwsRangeError);
      expect(await source.readRange(7, 3), [7, 8, 9]);
    });

    test('close is idempotent and rejects future reads', () async {
      final source = await VrlwFileSource.open(file.path);
      await source.close();
      await source.close();
      await expectLater(source.readRange(0, 1), throwsStateError);
    });

    test('rejects a size change after open', () async {
      final source = await VrlwFileSource.open(file.path);
      addTearDown(source.close);
      await file.writeAsBytes([1, 2, 3]);
      await expectLater(
        source.readRange(0, 1),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('rejects changed mtime even if the size is unchanged', () async {
      final source = await VrlwFileSource.open(file.path);
      addTearDown(source.close);
      final modified = (await file.stat()).modified;
      await file.setLastModified(modified.add(const Duration(seconds: 10)));
      await expectLater(
        source.readRange(0, 1),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('rejects missing, directory and symbolic link sources', () async {
      for (final path in [temporary.path, '${temporary.path}/missing']) {
        await expectLater(
          VrlwFileSource.open(path),
          throwsA(isA<FileSystemException>()),
        );
      }
      final link = Link('${temporary.path}/linked.vrlw');
      await link.create(file.path);
      await expectLater(
        VrlwFileSource.open(link.path),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('rejects an oversized sparse file without reading its body', () async {
      final handle = await file.open(mode: FileMode.write);
      await handle.truncate(VrlwByteSource.maxLength + 1);
      await handle.close();
      await expectLater(VrlwFileSource.open(file.path), throwsFormatException);
    });
  });
}
