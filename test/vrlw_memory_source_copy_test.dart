import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:vrlizate_world/vrlizate_world.dart';

void main() {
  test(
    'offset unmodifiable input still yields isolated mutable ranges',
    () async {
      final backing = Uint8List.fromList(List.generate(64, (i) => i));
      final view = Uint8List.view(backing.buffer, 7, 32).asUnmodifiableView();
      final source = VrlwMemorySource(view);
      addTearDown(source.close);
      backing.fillRange(0, backing.length, 255);
      final result = await source.readRange(5, 12);
      expect(result, List.generate(12, (i) => 12 + i));
      result[0] = 0;
      expect(await source.readRange(5, 12), List.generate(12, (i) => 12 + i));
      expect(source.length, 32);
    },
  );

  test('overlapping pending reads own independent writable buffers', () async {
    final source = VrlwMemorySource(
      Uint8List.fromList(List.generate(64, (i) => i)),
    );
    addTearDown(source.close);
    final results = await Future.wait([
      source.readRange(0, 32),
      source.readRange(16, 32),
      source.readRange(16, 32),
    ]);
    results[0].buffer.asUint8List(results[0].offsetInBytes + 16, 1)[0] = 200;
    expect(results[1][0], 16);
    expect(results[2][0], 16);
    results[1][1] = 201;
    expect(results[2][1], 17);
    expect(await source.readRange(16, 2), [16, 17]);
  });

  test(
    'exact read budget is accepted and excess fails within valid bounds',
    () async {
      const maximum = VrlwByteSource.maxReadLength;
      final input = Uint8List.fromList(
        List.generate(maximum + 2, (i) => (i * 13 + 7) & 255),
      );
      final source = VrlwMemorySource(input);
      addTearDown(source.close);
      final result = await source.readRange(1, maximum);
      expect(result, isA<Uint8List>());
      expect(result.length, maximum);
      expect(
        sha256.convert(result),
        sha256.convert(input.sublist(1, maximum + 1)),
      );
      // Fits the source, so this rejection specifically exercises the read cap.
      await expectLater(source.readRange(0, maximum + 1), throwsRangeError);
      expect(await source.readRange(maximum + 1, 1), [input.last]);
      await expectLater(source.readRange(maximum + 2, 1), throwsRangeError);
      await expectLater(source.readRange(0, 0), throwsRangeError);
    },
  );

  test(
    'close keeps completed reads and wins over later invalid ranges',
    () async {
      final source = VrlwMemorySource(Uint8List.fromList([1, 2, 3]));
      final pending = source.readRange(1, 2);
      final closing = source.close();
      await expectLater(source.readRange(0, 1), throwsStateError);
      await expectLater(source.readRange(-1, 0), throwsStateError);
      expect(await pending, [2, 3]);
      await closing;
      await source.close();
      expect(source.length, 3);
    },
  );
}
