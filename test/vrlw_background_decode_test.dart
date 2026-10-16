import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vrlizate_world/vrlizate_world.dart';

Map<String, Object?> _document(int count) => {
  'schemaVersion': 1,
  'id': 'test.background',
  'title': 'Background decode',
  'revision': '1',
  'license': 'CC0-1.0',
  'gridId': 'local-12m',
  'cellSizeMeters': 12,
  'origin': {'type': 'local'},
  'prototypes': ['tree'],
  'regions': [
    {
      'x': 2,
      'z': -1,
      'entities': [
        for (var i = 0; i < count; i++)
          {
            'id': 'tree:$i',
            'prototypeId': 'tree',
            'x': ((i % 64) + .5) * 12 / 64,
            'y': i % 7,
            'z': ((i ~/ 64) + .5) * 12 / 64,
            'yawRadians': (i % 8) * .5,
            'scale': 1 + (i % 4) * .25,
          },
      ],
    },
  ],
};

final class _Fixture {
  _Fixture(int count) {
    bytes = VrlwBundleCodec.encode(_document(count));
    final header = VrlwBundleCodec.parseHeader(bytes.sublist(0, 16));
    index = VrlwBundleCodec.parseIndex(
      header,
      bytes.sublist(16, header.payloadOffset),
    );
    chunk = index.chunkAt(2, -1)!;
    packed = bytes.sublist(header.payloadOffset + chunk.offset);
    world = VrWorldAddress(worldId: index.id, instanceId: 'local');
  }

  late final Uint8List bytes;
  late final VrlwBundleIndex index;
  late final VrlwChunkIndex chunk;
  late final Uint8List packed;
  late final VrWorldAddress world;

  FutureOr<List<VrWorldEntity>> decode(
    VrlwChunkDecoder decoder, {
    Uint8List? input,
    Set<String> prototypes = const {'tree'},
  }) => decoder.decode(
    index: index,
    chunk: chunk,
    packedBytes: input ?? packed,
    world: world,
    registeredPrototypeIds: prototypes,
  );

  Future<VrlwPlaceReader> open({Uint8List? input}) => VrlwPlaceReader.open(
    VrlwMemorySource(input ?? bytes),
    registeredPrototypeIds: {'tree'},
  );
}

// Real decode completes first. A gate then lets the test close/cancel exactly
// before provider adoption, without timer races or replacing codec validation.
final class _GatedDecoder implements VrlwChunkDecoder {
  final decoded = Completer<void>();
  final release = Completer<void>();

  @override
  Future<List<VrWorldEntity>> decode({
    required VrlwBundleIndex index,
    required VrlwChunkIndex chunk,
    required Uint8List packedBytes,
    required VrWorldAddress world,
    required Set<String> registeredPrototypeIds,
  }) async {
    final result = await const DefaultVrlwChunkDecoder().decode(
      index: index,
      chunk: chunk,
      packedBytes: packedBytes,
      world: world,
      registeredPrototypeIds: registeredPrototypeIds,
    );
    decoded.complete();
    await release.future;
    return result;
  }
}

final class _InspectableSource implements VrlwByteSource {
  _InspectableSource(Uint8List bytes) : inner = VrlwMemorySource(bytes);
  final VrlwMemorySource inner;
  late Uint8List lastRead;

  @override
  int get length => inner.length;

  @override
  Future<void> close() => inner.close();

  @override
  Future<Uint8List> readRange(int offset, int length) async {
    lastRead = await inner.readRange(offset, length);
    return lastRead;
  }
}

List<Object> _values(List<VrWorldEntity> entities) => [
  for (final entity in entities)
    (
      entity.id,
      entity.prototypeId,
      entity.world,
      entity.transform.position,
      entity.transform.yawRadians,
      entity.transform.scale,
    ),
];

void main() {
  const decoder = DefaultVrlwChunkDecoder();
  late _Fixture large;
  setUpAll(() {
    large = _Fixture(1024);
    expect(
      large.chunk.unpackedBytes,
      greaterThan(DefaultVrlwChunkDecoder.backgroundThresholdBytes),
    );
  });

  test('small regions retain synchronous decoding', () {
    final small = _Fixture(4);
    final result = small.decode(decoder);
    expect(result, isA<List<VrWorldEntity>>());
    expect(result, hasLength(4));
  });

  test('large native result equals codec and owns mutable input', () async {
    final expected = VrlwBundleCodec.decodeChunk(
      large.index,
      large.chunk,
      large.packed,
      world: large.world,
      registeredPrototypeIds: {'tree'},
    );
    final input = Uint8List.fromList(large.packed);
    final result = large.decode(decoder, input: input);
    expect(result, isA<Future<List<VrWorldEntity>>>());
    input.fillRange(0, input.length, 0);
    expect(_values(await result), _values(expected));
  });

  test('large blocks keep integrity and prototype validation', () async {
    final corrupt = Uint8List.fromList(large.packed)..[0] ^= 1;
    await expectLater(
      large.decode(decoder, input: corrupt),
      throwsFormatException,
    );
    await expectLater(
      large.decode(decoder, prototypes: {}),
      throwsFormatException,
    );
    expect(
      () => large.decode(decoder, input: Uint8List(1)),
      throwsFormatException,
    );
  });

  test('large corrupt cached bytes refetch and validate one region', () async {
    final reader = await large.open();
    addTearDown(reader.close);
    final corrupt = Uint8List.fromList(large.packed)..[0] ^= 1;
    var writes = 0;
    final provider = VrlwRegionProvider(
      reader,
      readCache: (_) async => corrupt,
      writeCache: (_, bytes) async {
        writes++;
        expect(bytes, large.packed);
        return true;
      },
    );
    final result = await provider.load(
      provider.grid.key(2, -1),
      VrRegionCancellation(),
    );
    expect(result.value, hasLength(1024));
    expect(provider.sourceReads, 1);
    expect(provider.cacheHits, 0);
    expect(writes, 1);
  });

  test('large corrupt source is not cached or adopted', () async {
    final corrupt = Uint8List.fromList(large.bytes);
    corrupt[large.index.header.payloadOffset] ^= 1;
    final reader = await large.open(input: corrupt);
    addTearDown(reader.close);
    var writes = 0;
    final provider = VrlwRegionProvider(
      reader,
      writeCache: (_, _) async {
        writes++;
        return true;
      },
    );
    await expectLater(
      provider.load(provider.grid.key(2, -1), VrRegionCancellation()),
      throwsFormatException,
    );
    expect(writes, 0);
  });

  test(
    'cache writes own source bytes throughout asynchronous decode',
    () async {
      final source = _InspectableSource(large.bytes);
      final reader = await VrlwPlaceReader.open(
        source,
        registeredPrototypeIds: {'tree'},
      );
      addTearDown(reader.close);
      final gate = _GatedDecoder();
      Uint8List? written;
      final provider = VrlwRegionProvider(
        reader,
        chunkDecoder: gate,
        writeCache: (_, bytes) async {
          written = bytes;
          return true;
        },
      );
      final load = provider.load(
        provider.grid.key(2, -1),
        VrRegionCancellation(),
      );
      await gate.decoded.future;
      source.lastRead.fillRange(0, source.lastRead.length, 0);
      gate.release.complete();
      expect((await load).value, hasLength(1024));
      expect(written, large.packed);
    },
  );

  for (final cached in [false, true]) {
    final path = cached ? 'cached' : 'source';
    test('closed reader discards late $path decode without writing', () async {
      final reader = await large.open();
      addTearDown(reader.close);
      final gate = _GatedDecoder();
      var writes = 0;
      final provider = VrlwRegionProvider(
        reader,
        chunkDecoder: gate,
        readCache: cached ? (_) async => large.packed : null,
        writeCache: (_, _) async {
          writes++;
          return true;
        },
      );
      final load = provider.load(
        provider.grid.key(2, -1),
        VrRegionCancellation(),
      );
      final rejected = expectLater(load, throwsStateError);
      await gate.decoded.future;
      await reader.close();
      gate.release.complete();
      await rejected;
      expect(writes, 0);
      expect(provider.cacheHits, 0);
    });

    test(
      'cancelled cache discards late $path decode without writing',
      () async {
        final reader = await large.open();
        addTearDown(reader.close);
        final gate = _GatedDecoder();
        var writes = 0;
        final provider = VrlwRegionProvider(
          reader,
          chunkDecoder: gate,
          readCache: cached ? (_) async => large.packed : null,
          writeCache: (_, _) async {
            writes++;
            return true;
          },
        );
        final completed = Completer<Object>();
        final cache = VrRegionCache<List<VrWorldEntity>>(
          grid: provider.grid,
          provider: (key, cancellation) async {
            try {
              final result = await provider.load(key, cancellation);
              completed.complete(result);
              return result;
            } catch (error) {
              completed.complete(error);
              rethrow;
            }
          },
          prefetchRadiusCells: 0,
          retentionRadiusCells: 0,
        );
        addTearDown(cache.dispose);
        cache.updatePosition(VrWorldPosition(25, 0, -11));
        await gate.decoded.future;
        cache.dispose();
        gate.release.complete();
        expect(await completed.future, isA<VrRegionLoadCancelled>());
        expect(writes, 0);
        expect(provider.cacheHits, 0);
      },
    );
  }
}
