import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:vrlizate_world/vrlizate_world.dart';

final world = VrWorldAddress(worldId: 'earth', instanceId: 'private');

Map<String, Object?> entity(String id, {String prototype = 'tree'}) => {
  'id': id,
  'prototypeId': prototype,
  'x': 2,
  'y': 3,
  'z': 4,
};

Map<String, Object?> source({List<Object?>? regions}) => {
  'schemaVersion': 1,
  'id': 'forest',
  'title': 'Bosque de prueba',
  'revision': '1.0.0',
  'license': 'CC0-1.0',
  'gridId': 'forest-origin-v1',
  'cellSizeMeters': 64,
  'prototypes': ['tree'],
  'regions':
      regions ??
      [
        {
          'x': -1,
          'z': 2,
          'entities': [entity('oak-1')],
        },
      ],
};

VrlwBundleIndex indexOf(List<int> bytes) {
  final header = VrlwBundleCodec.parseHeader(bytes.sublist(0, 16));
  expect(header.totalLength, bytes.length);
  return VrlwBundleCodec.parseIndex(
    header,
    bytes.sublist(16, header.payloadOffset),
  );
}

List<int> payloadOf(
  List<int> bytes,
  VrlwBundleIndex index,
  VrlwChunkIndex chunk,
) => bytes.sublist(
  index.header.payloadOffset + chunk.offset,
  index.header.payloadOffset + chunk.offset + chunk.packedBytes,
);

Map<String, Object?> indexJson(List<int> bytes) {
  final header = VrlwBundleCodec.parseHeader(bytes.sublist(0, 16));
  return (jsonDecode(utf8.decode(bytes.sublist(16, header.payloadOffset)))
          as Map<String, dynamic>)
      .cast<String, Object?>();
}

Uint8List makeBundle(Map<String, Object?> manifest, List<int> payload) {
  final index = utf8.encode(jsonEncode(manifest));
  final header = Uint8List(16)..setRange(0, 8, ascii.encode('VRLW0001'));
  ByteData.sublistView(header)
    ..setUint32(8, index.length, Endian.little)
    ..setUint32(12, payload.length, Endian.little);
  return (BytesBuilder()
        ..add(header)
        ..add(index)
        ..add(payload))
      .takeBytes();
}

Uint8List customPayload(
  List<int> payload, {
  String codec = 'store',
  int? unpackedBytes,
}) {
  final baseline = VrlwBundleCodec.encode(source());
  final manifest = indexJson(baseline);
  final chunk = (manifest['chunks'] as List).single as Map;
  chunk['codec'] = codec;
  chunk['packedBytes'] = payload.length;
  chunk['unpackedBytes'] = unpackedBytes ?? payload.length;
  chunk['sha256'] = sha256.convert(payload).toString();
  return makeBundle(manifest, payload);
}

List<VrWorldEntity> decodeOnly(
  List<int> bundle, {
  Set<String> registered = const {'tree'},
}) {
  final index = indexOf(bundle);
  final chunk = index.chunks.single;
  return VrlwBundleCodec.decodeChunk(
    index,
    chunk,
    payloadOf(bundle, index, chunk),
    world: world,
    registeredPrototypeIds: registered,
  );
}

void main() {
  test(
    'stored data roundtrips with region-local coordinates and host identity',
    () {
      final bytes = VrlwBundleCodec.encode(source(), compress: false);
      final index = indexOf(bytes);
      expect(index.id, 'forest');
      expect(index.title, 'Bosque de prueba');
      expect(index.prototypeIds, {'tree'});
      expect(index.origin, {'type': 'local'});
      expect(index.chunks.single.codec, 'store');
      expect(index.chunkAt(-1, 2), same(index.chunks.single));
      expect(index.chunkAt(0, 0), isNull);
      expect(
        index.indexSha256,
        sha256
            .convert(bytes.sublist(16, index.header.payloadOffset))
            .toString(),
      );
      final object = decodeOnly(bytes).single;
      expect(object.id, 'oak-1');
      expect(object.world, world);
      expect(object.transform.position, VrWorldPosition(-62, 3, 132));
      expect(object.transform.scale, 1);
    },
  );

  test(
    'independent DEFLATE chunks save bytes and decode only selected region',
    () {
      final document = source(
        regions: [
          for (var region = 0; region < 3; region++)
            {
              'x': region,
              'z': 0,
              'entities': [
                for (var i = 0; i < 100; i++) entity('tree-$region-$i'),
              ],
            },
        ],
      );
      final packed = VrlwBundleCodec.encode(document);
      final stored = VrlwBundleCodec.encode(document, compress: false);
      expect(packed.length, lessThan(stored.length ~/ 3));
      final index = indexOf(packed);
      expect(index.chunks.map((chunk) => chunk.codec), everyElement('deflate'));
      final chunk = index.chunkAt(1, 0)!;
      final result = VrlwBundleCodec.decodeChunk(
        index,
        chunk,
        payloadOf(packed, index, chunk),
        world: world,
        registeredPrototypeIds: {'tree'},
      );
      expect(result, hasLength(100));
      expect(result.first.id, 'tree-1-0');
      expect(result.first.transform.position.x, 66);
    },
  );

  test('compiler is deterministic for identical authoring input', () {
    expect(VrlwBundleCodec.encode(source()), VrlwBundleCodec.encode(source()));
  });

  test('empty bundle and empty region are valid bounded data', () {
    final empty = indexOf(VrlwBundleCodec.encode(source(regions: [])));
    expect(empty.chunks, isEmpty);
    expect(empty.header.packedPayloadLength, 0);
    expect(
      decodeOnly(
        VrlwBundleCodec.encode(
          source(
            regions: [
              {'x': 0, 'z': 0, 'entities': <Object?>[]},
            ],
          ),
        ),
      ),
      isEmpty,
    );
  });

  test(
    'Earth origin is metadata and does not silently transform coordinates',
    () {
      final document = source()
        ..['origin'] = {
          'type': 'wgs84-enu',
          'latitudeDegrees': 19.43,
          'longitudeDegrees': -99.13,
          'ellipsoidalHeightMeters': 2240,
        };
      final bytes = VrlwBundleCodec.encode(document);
      expect(indexOf(bytes).origin['type'], 'wgs84-enu');
      expect(
        decodeOnly(bytes).single.transform.position,
        VrWorldPosition(-62, 3, 132),
      );
    },
  );

  test('parsed collections cannot be changed after validation', () {
    final index = indexOf(VrlwBundleCodec.encode(source()));
    expect(() => index.chunks.clear(), throwsUnsupportedError);
    expect(() => index.prototypeIds.add('code'), throwsUnsupportedError);
    expect(() => index.origin['type'] = 'other', throwsUnsupportedError);
  });

  test(
    'header rejects bad versions, truncation and oversized file declarations',
    () {
      final valid = VrlwBundleCodec.encode(source()).sublist(0, 16);
      expect(
        () => VrlwBundleCodec.parseHeader(valid.sublist(1)),
        throwsFormatException,
      );
      final badMagic = Uint8List.fromList(valid)..[7] = 50;
      expect(
        () => VrlwBundleCodec.parseHeader(badMagic),
        throwsFormatException,
      );
      for (final (position, length) in [
        (8, 0),
        (8, VrlwBundleCodec.maxManifestBytes + 1),
        (12, VrlwBundleCodec.maxFileBytes),
      ]) {
        final mutated = Uint8List.fromList(valid);
        ByteData.sublistView(
          mutated,
        ).setUint32(position, length, Endian.little);
        expect(
          () => VrlwBundleCodec.parseHeader(mutated),
          throwsFormatException,
        );
      }
    },
  );

  test('index rejects unsupported schema and codec', () {
    final original = VrlwBundleCodec.encode(source(), compress: false);
    final originalIndex = indexOf(original);
    final payload = original.sublist(originalIndex.header.payloadOffset);
    for (final version in [2, '1', 1.0]) {
      final manifest = indexJson(original)..['schemaVersion'] = version;
      expect(
        () => indexOf(makeBundle(manifest, payload)),
        throwsFormatException,
      );
    }
    final manifest = indexJson(original);
    ((manifest['chunks'] as List).first as Map)['codec'] = 'dart';
    expect(() => indexOf(makeBundle(manifest, payload)), throwsFormatException);
  });

  test(
    'index rejects duplicate cells, overlap, gaps and unindexed trailing bytes',
    () {
      final bytes = VrlwBundleCodec.encode(source(), compress: false);
      final payload = bytes.sublist(indexOf(bytes).header.payloadOffset);
      final duplicate = indexJson(bytes);
      final chunks = duplicate['chunks'] as List;
      chunks.add(Map.from(chunks.single as Map));
      expect(
        () => indexOf(makeBundle(duplicate, [...payload, ...payload])),
        throwsFormatException,
      );
      for (final offset in [-1, 1]) {
        final manifest = indexJson(bytes);
        ((manifest['chunks'] as List).first as Map)['offset'] = offset;
        expect(
          () => indexOf(makeBundle(manifest, payload)),
          throwsFormatException,
        );
      }
      expect(
        () => indexOf(makeBundle(indexJson(bytes), [...payload, 0])),
        throwsFormatException,
      );
    },
  );

  test(
    'index rejects chunk, aggregate output and region count budget breaches',
    () {
      final bytes = VrlwBundleCodec.encode(source());
      final payload = bytes.sublist(indexOf(bytes).header.payloadOffset);
      for (final (field, value) in [
        ('packedBytes', VrlwBundleCodec.maxPackedChunkBytes + 1),
        ('unpackedBytes', VrlwBundleCodec.maxUnpackedChunkBytes + 1),
        ('unpackedBytes', 0),
      ]) {
        final manifest = indexJson(bytes);
        ((manifest['chunks'] as List).first as Map)[field] = value;
        expect(
          () => indexOf(makeBundle(manifest, payload)),
          throwsFormatException,
        );
      }
      final oversized = indexJson(bytes)
        ..['chunks'] = [
          for (var i = 0; i < 129; i++)
            {
              'x': i,
              'z': 0,
              'offset': i,
              'packedBytes': 1,
              'unpackedBytes': VrlwBundleCodec.maxUnpackedChunkBytes,
              'codec': 'deflate',
              'sha256': '0' * 64,
            },
        ];
      expect(
        () => indexOf(makeBundle(oversized, List.filled(129, 0))),
        throwsFormatException,
      );
      oversized['chunks'] = List.filled(1025, {});
      expect(() => indexOf(makeBundle(oversized, [])), throwsFormatException);
    },
  );

  test('integrity hash and packed length are checked before decoding', () {
    final bytes = VrlwBundleCodec.encode(source());
    final index = indexOf(bytes);
    final chunk = index.chunks.single;
    final packed = payloadOf(bytes, index, chunk);
    packed[0] ^= 0xff;
    expect(
      () => VrlwBundleCodec.decodeChunk(
        index,
        chunk,
        packed,
        world: world,
        registeredPrototypeIds: {'tree'},
      ),
      throwsFormatException,
    );
    expect(
      () => VrlwBundleCodec.decodeChunk(
        index,
        chunk,
        packed.sublist(1),
        world: world,
        registeredPrototypeIds: {'tree'},
      ),
      throwsFormatException,
    );
  });

  test('chunk cannot be substituted from a different parsed index', () {
    final bytes = VrlwBundleCodec.encode(source());
    final index = indexOf(bytes);
    final other = indexOf(bytes);
    expect(
      () => VrlwBundleCodec.decodeChunk(
        index,
        other.chunks.single,
        payloadOf(bytes, index, index.chunks.single),
        world: world,
        registeredPrototypeIds: {'tree'},
      ),
      throwsFormatException,
    );
  });

  test(
    'DEFLATE bomb aborts at declared output before allocating expansion',
    () {
      final packed = Deflate(List.filled(500000, 32)).getBytes();
      final bytes = customPayload(packed, codec: 'deflate', unpackedBytes: 32);
      expect(() => decodeOnly(bytes), throwsFormatException);
    },
  );

  test('malformed, truncated and trailing DEFLATE input is rejected', () {
    final data = utf8.encode(
      jsonEncode({
        'entities': [entity('tree-1')],
      }),
    );
    final packed = Deflate(data).getBytes();
    for (final invalid in [
      <int>[7, 255],
      packed.sublist(0, packed.length ~/ 2),
      [...packed, 255, 255],
    ]) {
      expect(
        () => decodeOnly(
          customPayload(invalid, codec: 'deflate', unpackedBytes: data.length),
        ),
        throwsFormatException,
      );
    }
  });

  test('STORE length mismatches and invalid UTF-8 are rejected', () {
    expect(
      () => indexOf(customPayload([123, 125], unpackedBytes: 3)),
      throwsFormatException,
    );
    expect(() => decodeOnly(customPayload([255, 255])), throwsFormatException);
  });

  test('a nonfinal DEFLATE block cannot masquerade as a complete region', () {
    final data = utf8.encode(
      jsonEncode({
        'entities': [entity('tree-1')],
      }),
    );
    final length = data.length;
    final complement = length ^ 0xffff;
    // RFC1951 uncompressed block with BFINAL=0 and all bytes present, but no
    // final block. Merely checking output length accepts this truncated stream.
    final unfinished = [
      0,
      length & 255,
      length >> 8,
      complement & 255,
      complement >> 8,
      ...data,
    ];
    expect(
      () => decodeOnly(
        customPayload(unfinished, codec: 'deflate', unpackedBytes: length),
      ),
      throwsFormatException,
    );
  });

  test('deep JSON and malformed JSON cannot bypass bounded schema', () {
    final deep = utf8.encode('${'[' * 10000}0${']' * 10000}');
    expect(() => decodeOnly(customPayload(deep)), throwsFormatException);
    expect(
      () => decodeOnly(customPayload(utf8.encode('{bad}'))),
      throwsFormatException,
    );
    final header = Uint8List(16)..setRange(0, 8, ascii.encode('VRLW0001'));
    ByteData.sublistView(header).setUint32(8, deep.length, Endian.little);
    expect(
      () =>
          VrlwBundleCodec.parseIndex(VrlwBundleCodec.parseHeader(header), deep),
      throwsFormatException,
    );
  });

  test('runtime rejects undeclared or unregistered prototype references', () {
    final bytes = VrlwBundleCodec.encode(source());
    expect(() => decodeOnly(bytes, registered: {}), throwsFormatException);
    final undeclared = utf8.encode(
      jsonEncode({
        'entities': [entity('object-1', prototype: 'untrusted-script')],
      }),
    );
    expect(
      () => decodeOnly(
        customPayload(undeclared),
        registered: {'untrusted-script'},
      ),
      throwsFormatException,
    );
  });

  test(
    'entity local bounds, scale and fields are checked during lazy decode',
    () {
      for (final patch in [
        {'x': -1},
        {'x': 64},
        {'z': 64},
        {'y': 10000001},
        {'scale': 0},
        {'scale': 1001},
        {'yawRadians': 'nan'},
        {'code': 'run()'},
        {'id': '../escape'},
        {'prototypeId': 'https://example.test/script'},
      ]) {
        final payload = utf8.encode(
          jsonEncode({
            'entities': [
              {...entity('object-1'), ...patch},
            ],
          }),
        );
        expect(
          () => decodeOnly(customPayload(payload)),
          throwsFormatException,
          reason: '$patch',
        );
      }
    },
  );

  test('runtime rejects duplicate IDs within a selected chunk', () {
    final payload = utf8.encode(
      jsonEncode({
        'entities': [entity('same'), entity('same')],
      }),
    );
    expect(() => decodeOnly(customPayload(payload)), throwsFormatException);
  });

  test('compiler rejects duplicate IDs across separately loaded regions', () {
    final document = source(
      regions: [
        {
          'x': 0,
          'z': 0,
          'entities': [entity('same')],
        },
        {
          'x': 1,
          'z': 0,
          'entities': [entity('same')],
        },
      ],
    );
    expect(() => VrlwBundleCodec.encode(document), throwsFormatException);
  });

  test('compiler rejects duplicate regions and prototype declarations', () {
    final duplicateRegion = source(
      regions: [
        {
          'x': 0,
          'z': 0,
          'entities': [entity('one')],
        },
        {
          'x': 0,
          'z': 0,
          'entities': [entity('two')],
        },
      ],
    );
    expect(
      () => VrlwBundleCodec.encode(duplicateRegion),
      throwsFormatException,
    );
    expect(
      () => VrlwBundleCodec.encode(source()..['prototypes'] = ['tree', 'tree']),
      throwsFormatException,
    );
  });

  test('source budgets reject excessive entities before serialization', () {
    expect(
      () => VrlwBundleCodec.encode(
        source(
          regions: [
            {'x': 0, 'z': 0, 'entities': List.filled(4097, entity('one'))},
          ],
        ),
      ),
      throwsFormatException,
    );
  });

  test('origin, cell extent and finite numeric constraints are enforced', () {
    for (final patch in [
      {'cellSizeMeters': double.nan},
      {'cellSizeMeters': 0.01},
      {'cellSizeMeters': double.infinity},
      {
        'origin': {'type': 'ecef'},
      },
      {
        'origin': {
          'type': 'wgs84-enu',
          'latitudeDegrees': 91,
          'longitudeDegrees': 0,
          'ellipsoidalHeightMeters': 0,
        },
      },
      {
        'origin': {
          'type': 'wgs84-enu',
          'latitudeDegrees': 0,
          'longitudeDegrees': 0,
          'ellipsoidalHeightMeters': 1000001,
        },
      },
      {'executable': 'experience.dart'},
    ]) {
      expect(
        () => VrlwBundleCodec.encode({...source(), ...patch}),
        throwsFormatException,
      );
    }
    expect(
      () => VrlwBundleCodec.encode(
        source(
          regions: [
            {'x': 156250, 'z': 0, 'entities': <Object?>[]},
          ],
        ),
      ),
      throwsFormatException,
    );
  });
}
