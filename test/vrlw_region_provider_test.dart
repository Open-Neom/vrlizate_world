import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vrlizate_world/vrlizate_world.dart';

Map<String, Object?> sourceDocument({String revision = '1'}) => {
  'schemaVersion': 1,
  'id': 'test.place',
  'title': 'Test place',
  'revision': revision,
  'license': 'CC0-1.0',
  'gridId': 'local0-12m',
  'cellSizeMeters': 12,
  'origin': {'type': 'local'},
  'prototypes': ['tree'],
  'regions': [
    for (var x = 0; x < 8; x++)
      {
        'x': x,
        'z': 0,
        'entities': [
          for (var i = 0; i < 8; i++)
            {
              'id': 'tree:$x:$i',
              'prototypeId': 'tree',
              'x': i + .5,
              'y': 0,
              'z': 2,
              'scale': 1,
            },
        ],
      },
  ],
};

class CountingSource implements VrlwByteSource {
  CountingSource(Uint8List bytes) : inner = VrlwMemorySource(bytes);
  final VrlwMemorySource inner;
  final reads = <(int, int)>[];
  @override
  int get length => inner.length;
  @override
  Future<void> close() => inner.close();
  @override
  Future<Uint8List> readRange(int offset, int length) {
    reads.add((offset, length));
    return inner.readRange(offset, length);
  }
}

void main() {
  test(
    'closing rejects both late cache hits and absent-region reads',
    () async {
      final bytes = VrlwBundleCodec.encode(sourceDocument());
      final reader = await VrlwPlaceReader.open(
        VrlwMemorySource(bytes),
        registeredPrototypeIds: {'tree'},
      );
      final chunk = reader.index.chunkAt(0, 0)!;
      final start = reader.index.header.payloadOffset + chunk.offset;
      final pendingCache = Completer<Uint8List?>();
      final provider = VrlwRegionProvider(
        reader,
        readCache: (_) => pendingCache.future,
      );
      final load = provider.load(
        provider.grid.key(0, 0),
        VrRegionCancellation(),
      );
      final rejected = expectLater(load, throwsStateError);
      await reader.close();
      pendingCache.complete(bytes.sublist(start, start + chunk.packedBytes));
      await rejected;
      expect(provider.cacheHits, 0);
      await expectLater(
        provider.load(provider.grid.key(-1, -1), VrRegionCancellation()),
        throwsStateError,
      );
    },
  );
  test(
    'opens only index, then a selected block through the existing region cache',
    () async {
      final bytes = VrlwBundleCodec.encode(sourceDocument());
      final source = CountingSource(bytes);
      final reader = await VrlwPlaceReader.open(
        source,
        registeredPrototypeIds: {'tree'},
      );
      addTearDown(reader.close);
      expect(source.reads.length, 2);
      expect(
        source.reads.last.$1 + source.reads.last.$2,
        reader.index.header.payloadOffset,
      );
      final provider = VrlwRegionProvider(reader);
      final cache = VrRegionCache<List<VrWorldEntity>>(
        grid: provider.grid,
        provider: provider.load,
        prefetchRadiusCells: 0,
        retentionRadiusCells: 0,
      );
      addTearDown(cache.dispose);
      cache.updatePosition(VrWorldPosition(37, 1.6, 1));
      await cache.waitForIdle();
      expect(source.reads.length, 3);
      final chunk = reader.index.chunkAt(3, 0)!;
      expect(source.reads.last, (
        reader.index.header.payloadOffset + chunk.offset,
        chunk.packedBytes,
      ));
      expect(
        cache.snapshot.currentData!.value.first.transform.position.x,
        36.5,
      );
      expect(cache.snapshot.currentData!.value, hasLength(8));
      expect(
        source.reads.fold<int>(0, (n, r) => n + r.$2),
        lessThan(bytes.length),
      );
      cache.updatePosition(VrWorldPosition(38, 1.6, 2));
      await cache.waitForIdle();
      expect(source.reads.length, 3);
    },
  );

  test(
    'compressed cache survives provider replacement and corruption refetches one block',
    () async {
      final disk = <String, Uint8List>{};
      final bytes = VrlwBundleCodec.encode(sourceDocument());
      Future<VrlwRegionProvider> provider() async => VrlwRegionProvider(
        await VrlwPlaceReader.open(
          VrlwMemorySource(bytes),
          registeredPrototypeIds: {'tree'},
        ),
        readCache: (key) async => disk[key],
        writeCache: (key, value) async {
          disk[key] = value;
          return true;
        },
      );
      Future<void> visit(VrlwRegionProvider p) async {
        final cache = VrRegionCache<List<VrWorldEntity>>(
          grid: p.grid,
          provider: p.load,
          prefetchRadiusCells: 0,
          retentionRadiusCells: 0,
        );
        cache.updatePosition(VrWorldPosition.zero);
        await cache.waitForIdle();
        expect(cache.snapshot.errors, isEmpty);
        expect(cache.snapshot.currentData!.value, hasLength(8));
        cache.dispose();
        await p.reader.close();
      }

      final first = await provider();
      await visit(first);
      expect(first.sourceReads, 1);
      final reopened = await provider();
      await visit(reopened);
      expect(reopened.sourceReads, 0);
      expect(reopened.cacheHits, 1);
      disk[disk.keys.single] = Uint8List.fromList([0, 1, 2]);
      final corrupt = await provider();
      await visit(corrupt);
      expect(corrupt.sourceReads, 1);
    },
  );

  test(
    'changed revision gets a different cache namespace and pins the trusted index',
    () async {
      Future<VrlwPlaceReader> open(String revision, {String? pin}) =>
          VrlwPlaceReader.open(
            VrlwMemorySource(
              VrlwBundleCodec.encode(sourceDocument(revision: revision)),
            ),
            registeredPrototypeIds: {'tree'},
            expectedIndexSha256: pin,
          );
      final first = await open('1');
      final second = await open('2');
      addTearDown(first.close);
      addTearDown(second.close);
      expect(
        VrlwRegionProvider(first).grid.gridId,
        isNot(VrlwRegionProvider(second).grid.gridId),
      );
      await expectLater(
        open('2', pin: first.index.indexSha256),
        throwsFormatException,
      );
    },
  );

  test(
    'unknown runtime prototypes are rejected before any region read',
    () async {
      final source = CountingSource(VrlwBundleCodec.encode(sourceDocument()));
      await expectLater(
        VrlwPlaceReader.open(source, registeredPrototypeIds: {}),
        throwsFormatException,
      );
      expect(source.reads, hasLength(2));
      await source.close();
    },
  );

  test(
    'absent cells are empty without reading payload and foreign keys fail',
    () async {
      final source = CountingSource(VrlwBundleCodec.encode(sourceDocument()));
      final reader = await VrlwPlaceReader.open(
        source,
        registeredPrototypeIds: {'tree'},
      );
      addTearDown(reader.close);
      final provider = VrlwRegionProvider(reader);
      final result = await provider.load(
        provider.grid.key(-1, -1),
        VrRegionCancellation(),
      );
      expect(result.value, isEmpty);
      expect(source.reads, hasLength(2));
      final foreign = VrRegionGrid(
        world: VrWorldAddress(worldId: 'other', instanceId: 'local'),
        gridId: provider.grid.gridId,
      );
      await expectLater(
        provider.load(foreign.key(0, 0), VrRegionCancellation()),
        throwsFormatException,
      );
    },
  );
}
