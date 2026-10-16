import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:vrlizate_world/vrlizate_world.dart';

import 'vrlw_bundle_test.dart' as legacy;

Uint8List glbEnvelope({int binLength = 4}) {
  final json = [...utf8.encode('{"asset":{"version":"2.0"}}')];
  while (json.length % 4 != 0) {
    json.add(32);
  }
  final bytes = Uint8List(28 + json.length + binLength);
  final view = ByteData.sublistView(bytes);
  view
    ..setUint32(0, 0x46546c67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, bytes.length, Endian.little)
    ..setUint32(12, json.length, Endian.little)
    ..setUint32(16, 0x4e4f534a, Endian.little);
  bytes.setRange(20, 20 + json.length, json);
  view
    ..setUint32(20 + json.length, binLength, Endian.little)
    ..setUint32(24 + json.length, 0x004e4942, Endian.little);
  return bytes;
}

Map<String, Object?> resourceSource() => legacy.source()
  ..['resources'] = <Object?>[
    <String, Object?>{
      'id': 'oak-mesh',
      'type': 'model.glb',
      'data': base64.encode(glbEnvelope()),
    },
    <String, Object?>{
      'id': 'oak-color',
      'type': 'texture.rgba8',
      'data': base64.encode(List.filled(256, 255)),
      'width': 8,
      'height': 8,
    },
  ]
  ..['prototypeBindings'] = <Object?>[
    <String, Object?>{
      'prototypeId': 'tree',
      'model': 'oak-mesh',
      'baseColorTexture': 'oak-color',
    },
  ];

class RecordingSource implements VrlwByteSource {
  RecordingSource(this.bytes);
  final Uint8List bytes;
  final reads = <(int, int)>[];
  bool closed = false;
  Completer<void>? gate;
  bool truncate = false;
  @override
  int get length => bytes.length;
  @override
  Future<Uint8List> readRange(int offset, int length) async {
    validateVrlwRange(offset, length, totalLength: bytes.length);
    reads.add((offset, length));
    await gate?.future;
    return Uint8List.fromList(
      bytes.sublist(offset, offset + length - (truncate ? 1 : 0)),
    );
  }

  @override
  Future<void> close() async => closed = true;
}

Uint8List customResource(
  List<int> packed, {
  int unpacked = 4,
  String codec = 'deflate',
}) {
  final source = legacy.source(regions: [])
    ..['resources'] = [
      {
        'id': 'color',
        'type': 'texture.rgba8',
        'width': 1,
        'height': 1,
        'data': base64.encode([1, 2, 3, 4]),
      },
    ];
  final manifest = legacy.indexJson(VrlwBundleCodec.encode(source));
  final resource = (manifest['resources'] as List).single as Map;
  resource['codec'] = codec;
  resource['packedBytes'] = packed.length;
  resource['unpackedBytes'] = unpacked;
  resource['sha256'] = sha256.convert(packed).toString();
  return legacy.makeBundle(manifest, packed);
}

Uint8List decodeOnlyResource(Uint8List bytes) {
  final index = legacy.indexOf(bytes);
  final resource = index.resources.single;
  return VrlwBundleCodec.decodeResource(
    index,
    resource,
    bytes.sublist(index.header.payloadOffset),
  );
}

void main() {
  test(
    'legacy STORE and DEFLATE bytes remain identical without resource fields',
    () {
      final source = <String, Object?>{
        'schemaVersion': 1,
        'id': 'legacy',
        'title': 'Legacy',
        'revision': '1.0',
        'license': 'CC0-1.0',
        'gridId': 'grid',
        'cellSizeMeters': 12,
        'prototypes': ['tree'],
        'regions': [
          {
            'x': 0,
            'z': 0,
            'entities': [
              {'id': 'oak', 'prototypeId': 'tree', 'x': 2, 'y': 0, 'z': 3},
            ],
          },
        ],
      };
      for (final pair in [
        (
          true,
          '999bdc72a58ad9ea390b35fc3c929cf2b58480dc33e580ac6e77fb979f33a740',
        ),
        (
          false,
          '97124a2ea9f1bf5db78ab268642fd61c4a17160a7136a075723356694529e8f6',
        ),
      ]) {
        final bytes = VrlwBundleCodec.encode(source, compress: pair.$1);
        expect(sha256.convert(bytes).toString(), pair.$2);
        final index = legacy.indexOf(bytes);
        expect(index.resources, isEmpty);
        expect(index.prototypeBindings, isEmpty);
        expect(legacy.indexJson(bytes).containsKey('resources'), isFalse);
      }
    },
  );

  for (final compress in [false, true]) {
    test('resource roundtrip and lazy ranges (compress=$compress)', () async {
      final bytes = VrlwBundleCodec.encode(
        resourceSource(),
        compress: compress,
      );
      final source = RecordingSource(bytes);
      final reader = await VrlwPlaceReader.open(
        source,
        registeredPrototypeIds: {'tree'},
      );
      addTearDown(reader.close);
      expect(source.reads, hasLength(2));
      expect(reader.index.resources, hasLength(2));
      final binding = reader.index.prototypeBindings.single;
      expect(
        (binding.prototypeId, binding.model, binding.baseColorTexture),
        ('tree', 'oak-mesh', 'oak-color'),
      );
      final color = reader.index.resourceAt('oak-color')!;
      expect((color.width, color.height, color.unpackedBytes), (8, 8, 256));
      expect(await reader.readResource('oak-color'), List.filled(256, 255));
      expect(source.reads.last, (
        reader.index.header.payloadOffset + color.offset,
        color.packedBytes,
      ));
      expect(source.reads, hasLength(3));
      expect(await reader.readResource('oak-mesh'), glbEnvelope());
      expect(() => reader.index.resources.clear(), throwsUnsupportedError);
      expect(
        () => reader.index.prototypeBindings.clear(),
        throwsUnsupportedError,
      );
      expect(await reader.readResource('oak-color'), List.filled(256, 255));
      await expectLater(reader.readResource('absent'), throwsFormatException);
    });
  }

  test('resource bindings do not auto-register prototypes', () async {
    final source = VrlwMemorySource(VrlwBundleCodec.encode(resourceSource()));
    addTearDown(source.close);
    await expectLater(
      VrlwPlaceReader.open(source, registeredPrototypeIds: {}),
      throwsFormatException,
    );
  });

  test('resource blocks cannot be substituted across parsed owners', () {
    final bytes = VrlwBundleCodec.encode(resourceSource());
    final index = legacy.indexOf(bytes);
    final other = legacy.indexOf(bytes);
    final resource = index.resources.first;
    final packed = bytes.sublist(
      index.header.payloadOffset + resource.offset,
      index.header.payloadOffset + resource.offset + resource.packedBytes,
    );
    expect(
      () =>
          VrlwBundleCodec.decodeResource(index, other.resources.first, packed),
      throwsFormatException,
    );
    packed[0] ^= 1;
    expect(
      () => VrlwBundleCodec.decodeResource(index, resource, packed),
      throwsFormatException,
    );
    expect(
      () => VrlwBundleCodec.decodeResource(index, resource, packed.sublist(1)),
      throwsFormatException,
    );
  });

  test(
    'compiler rejects resource types, unknown fields, IDs and dimension mismatches',
    () {
      for (final patch in <Map<String, Object?>>[
        {'type': 'audio.script'},
        {'data': '**bad**'},
        {'id': '../escape'},
        {'width': 0},
        {'width': 513},
        {'width': 8.0},
        {'height': null},
        {'width': double.nan},
        {
          'data': base64.encode([0]),
        },
        {'url': 'https://example.test/image'},
      ]) {
        final source = resourceSource();
        final list = source['resources'] as List;
        list[1] = {...list[1] as Map<String, Object?>, ...patch};
        expect(
          () => VrlwBundleCodec.encode(source),
          throwsFormatException,
          reason: '$patch',
        );
      }
      final source = resourceSource();
      ((source['resources'] as List).first as Map)['width'] = 1;
      expect(() => VrlwBundleCodec.encode(source), throwsFormatException);
      for (final field in ['resources', 'prototypeBindings']) {
        expect(
          () => VrlwBundleCodec.encode(resourceSource()..[field] = null),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'bindings reject missing references, crossed roles and duplicate prototypes',
    () {
      for (final patch in [
        {'prototypeId': 'other'},
        {'model': 'absent'},
        {'model': 'oak-color'},
        {'baseColorTexture': 'oak-mesh'},
        {'baseColorTexture': 'absent'},
        {'script': 'run()'},
        {'baseColorTexture': null},
      ]) {
        final source = resourceSource();
        final bindings = source['prototypeBindings'] as List;
        bindings[0] = {...bindings[0] as Map, ...patch};
        expect(
          () => VrlwBundleCodec.encode(source),
          throwsFormatException,
          reason: '$patch',
        );
      }
      final duplicate = resourceSource();
      final bindings = duplicate['prototypeBindings'] as List;
      bindings.add(bindings.single);
      expect(() => VrlwBundleCodec.encode(duplicate), throwsFormatException);
      final duplicateResource = resourceSource();
      final resources = duplicateResource['resources'] as List;
      resources.add(resources.first);
      expect(
        () => VrlwBundleCodec.encode(duplicateResource),
        throwsFormatException,
      );
    },
  );

  test(
    'index enforces resource count, total budgets, ranges and roles before reads',
    () {
      final original = VrlwBundleCodec.encode(resourceSource());
      final payload = original.sublist(
        legacy.indexOf(original).header.payloadOffset,
      );
      for (final patch in <Map<String, Object?>>[
        {'offset': 0},
        {'offset': 999999},
        {'packedBytes': 0},
        {'unpackedBytes': VrlwBundleCodec.maxResourceBytes + 1},
        {'codec': 'gzip'},
        {'type': 'code.dart'},
        {'sha256': 'bad'},
        {'unknown': true},
      ]) {
        final manifest = legacy.indexJson(original);
        final resources = manifest['resources'] as List;
        resources[0] = {...resources[0] as Map, ...patch};
        expect(
          () => legacy.indexOf(legacy.makeBundle(manifest, payload)),
          throwsFormatException,
          reason: '$patch',
        );
      }
      final excess = legacy.indexJson(original)
        ..['resources'] = List.filled(33, {});
      expect(
        () => legacy.indexOf(legacy.makeBundle(excess, payload)),
        throwsFormatException,
      );
      final total = legacy.indexJson(original)
        ..['chunks'] = <Object>[]
        ..['prototypeBindings'] = <Object>[]
        ..['resources'] = [
          for (var i = 0; i < 17; i++)
            {
              'id': 'texture-$i',
              'type': 'texture.rgba8',
              'offset': i,
              'packedBytes': 1,
              'unpackedBytes': 1048576,
              'codec': 'deflate',
              'sha256': '0' * 64,
              'width': 512,
              'height': 512,
            },
        ];
      expect(
        () => legacy.indexOf(legacy.makeBundle(total, List.filled(17, 0))),
        throwsFormatException,
      );
      final role = legacy.indexJson(original);
      ((role['prototypeBindings'] as List).single as Map)['model'] =
          'oak-color';
      expect(
        () => legacy.indexOf(legacy.makeBundle(role, payload)),
        throwsFormatException,
      );
      expect(
        () => legacy.indexOf(
          legacy.makeBundle(legacy.indexJson(original), [...payload, 0]),
        ),
        throwsFormatException,
      );
    },
  );

  test('resource DEFLATE bombs, truncation and appended data are rejected', () {
    expect(
      () => decodeOnlyResource(
        customResource(Deflate(List.filled(500000, 0)).getBytes()),
      ),
      throwsFormatException,
    );
    final packed = Deflate([1, 2, 3, 4]).getBytes();
    expect(decodeOnlyResource(customResource(packed)), [1, 2, 3, 4]);
    for (final invalid in [
      packed.sublist(0, packed.length ~/ 2),
      [...packed, 42],
      [7, 255],
    ]) {
      expect(
        () => decodeOnlyResource(customResource(invalid)),
        throwsFormatException,
      );
    }
    expect(
      () => decodeOnlyResource(customResource([1, 2], codec: 'store')),
      throwsFormatException,
    );
  });

  test('GLB envelope rejects version, size, chunk kinds and trailing data', () {
    for (final (offset, value) in [
      (0, 0),
      (4, 1),
      (8, 0),
      (12, 0xffffffff),
      (16, 0),
    ]) {
      final malformed = glbEnvelope();
      ByteData.sublistView(malformed).setUint32(offset, value, Endian.little);
      final source = resourceSource();
      ((source['resources'] as List).first as Map)['data'] = base64.encode(
        malformed,
      );
      expect(() => VrlwBundleCodec.encode(source), throwsFormatException);
    }
  });

  test('large STORE resource uses bounded transport ranges', () async {
    final model = glbEnvelope(binLength: 2 * 1024 * 1024);
    final document = resourceSource();
    ((document['resources'] as List).first as Map)['data'] = base64.encode(
      model,
    );
    final source = RecordingSource(
      VrlwBundleCodec.encode(document, compress: false),
    );
    final reader = await VrlwPlaceReader.open(
      source,
      registeredPrototypeIds: {'tree'},
    );
    addTearDown(reader.close);
    expect(await reader.readResource('oak-mesh'), model);
    expect(
      source.reads,
      hasLength(5),
    ); // header, index and three bounded ranges.
    expect(
      source.reads.map((range) => range.$2),
      everyElement(lessThanOrEqualTo(VrlwByteSource.maxReadLength)),
    );
  });

  test(
    'short reads and late resource completions after close are rejected',
    () async {
      final bytes = VrlwBundleCodec.encode(resourceSource());
      final short = RecordingSource(bytes);
      final shortReader = await VrlwPlaceReader.open(
        short,
        registeredPrototypeIds: {'tree'},
      );
      addTearDown(shortReader.close);
      short.truncate = true;
      await expectLater(
        shortReader.readResource('oak-mesh'),
        throwsFormatException,
      );
      final source = RecordingSource(bytes);
      final reader = await VrlwPlaceReader.open(
        source,
        registeredPrototypeIds: {'tree'},
      );
      source.gate = Completer<void>();
      final pending = reader.readResource('oak-color');
      final rejection = expectLater(pending, throwsStateError);
      await reader.close();
      source.gate!.complete();
      await rejection;
      expect(source.closed, isTrue);
      await expectLater(reader.readResource('oak-color'), throwsStateError);
    },
  );

  test(
    'supports PNG/JPEG/KTX2 textures, PBR maps, audio, colliders, environment, and dependencies',
    () async {
      final png = Uint8List(36)
        ..setRange(0, 8, const [
          0x89,
          0x50,
          0x4e,
          0x47,
          0x0d,
          0x0a,
          0x1a,
          0x0a,
        ]);
      ByteData.sublistView(png)
        ..setUint32(8, 13)
        ..setUint32(12, 0x49484452)
        ..setUint32(16, 16)
        ..setUint32(20, 16);
      final jpeg = Uint8List.fromList([
        0xff,
        0xd8,
        ...List.filled(12, 0),
        0xff,
        0xd9,
      ]);
      final ktx2 = Uint8List(80)
        ..setRange(0, 12, const [
          0xab,
          0x4b,
          0x54,
          0x58,
          0x20,
          0x32,
          0x30,
          0xbb,
          0x0d,
          0x0a,
          0x1a,
          0x0a,
        ]);
      ByteData.sublistView(ktx2)
        ..setUint32(20, 64, Endian.little)
        ..setUint32(24, 64, Endian.little);
      final wav = Uint8List(44);
      ByteData.sublistView(wav)
        ..setUint32(0, 0x46464952, Endian.little)
        ..setUint32(8, 0x45564157, Endian.little);

      final doc = legacy.source()
        ..['resources'] = <Object?>[
          {
            'id': 'oak-mesh',
            'type': 'model.glb',
            'data': base64.encode(glbEnvelope()),
          },
          {
            'id': 'oak-albedo',
            'type': 'texture.png',
            'width': 16,
            'height': 16,
            'data': base64.encode(png),
          },
          {
            'id': 'oak-normal',
            'type': 'texture.jpeg',
            'data': base64.encode(jpeg),
          },
          {
            'id': 'oak-mr',
            'type': 'texture.ktx2',
            'width': 64,
            'height': 64,
            'data': base64.encode(ktx2),
          },
          {
            'id': 'sky-ibl',
            'type': 'environment.ktx2',
            'data': base64.encode(ktx2),
          },
          {
            'id': 'wind-sfx',
            'type': 'audio.wav',
            'data': base64.encode(wav),
          },
        ]
        ..['prototypeBindings'] = <Object?>[
          {
            'prototypeId': 'tree',
            'model': 'oak-mesh',
            'baseColorTexture': 'oak-albedo',
            'normalTexture': 'oak-normal',
            'metallicRoughnessTexture': 'oak-mr',
            'emissiveTexture': 'oak-albedo',
            'occlusionTexture': 'oak-mr',
            'audio': 'wind-sfx',
            'castsShadows': true,
            'collider': {
              'shape': 'cylinder',
              'radius': 0.45,
              'height': 3.2,
              'offset': [0.0, 1.6, 0.0],
            },
          },
        ]
        ..['environment'] = <String, Object?>{
          'environmentResource': 'sky-ibl',
          'skyboxResource': 'sky-ibl',
          'environmentIntensity': 1.2,
          'exposure': 1.1,
          'sunDirection': [-0.3, -1.0, -0.2],
          'sunColor': [1.0, 0.95, 0.9],
          'sunIntensity': 3.0,
          'castsShadows': true,
        }
        ..['audioEmitters'] = <Object?>[
          {
            'id': 'canopy-breeze',
            'resource': 'wind-sfx',
            'x': 2.0,
            'y': 1.8,
            'z': 3.0,
            'volume': 0.75,
            'maxDistance': 18.0,
            'loop': true,
          },
        ]
        ..['dependencies'] = <Object?>[
          {
            'alias': 'plaza',
            'id': 'plaza-world',
            'revision': '1.0',
            'indexSha256': 'a' * 64,
            'url': 'https://worlds.vrlizate.org/plaza.vrlw',
          },
        ];

      final encoded = VrlwBundleCodec.encode(doc);
      final reader = await VrlwPlaceReader.open(
        VrlwMemorySource(encoded),
        registeredPrototypeIds: {'tree'},
      );
      addTearDown(reader.close);

      final binding = reader.index.prototypeBindings.single;
      expect(binding.baseColorTexture, 'oak-albedo');
      expect(binding.normalTexture, 'oak-normal');
      expect(binding.metallicRoughnessTexture, 'oak-mr');
      expect(binding.emissiveTexture, 'oak-albedo');
      expect(binding.occlusionTexture, 'oak-mr');
      expect(binding.audio, 'wind-sfx');
      expect(binding.castsShadows, isTrue);
      expect(binding.collider?.shape, 'cylinder');
      expect(binding.collider?.radius, 0.45);
      expect(binding.collider?.height, 3.2);
      expect(binding.collider?.offset, [0.0, 1.6, 0.0]);

      final env = reader.index.environment!;
      expect(env.environmentResource, 'sky-ibl');
      expect(env.skyboxResource, 'sky-ibl');
      expect(env.environmentIntensity, 1.2);
      expect(env.exposure, 1.1);
      expect(env.sunIntensity, 3.0);
      expect(env.castsShadows, isTrue);

      final emitter = reader.index.audioEmitters.single;
      expect(emitter.id, 'canopy-breeze');
      expect(emitter.resource, 'wind-sfx');
      expect(emitter.volume, 0.75);
      expect(emitter.maxDistance, 18.0);
      expect(emitter.loop, isTrue);

      final dep = reader.index.dependencies.single;
      expect(dep.alias, 'plaza');
      expect(dep.id, 'plaza-world');
      expect(dep.url, 'https://worlds.vrlizate.org/plaza.vrlw');

      expect(await reader.readResource('oak-albedo'), png);
      expect(await reader.readResource('oak-normal'), jpeg);
      expect(await reader.readResource('oak-mr'), ktx2);
      expect(await reader.readResource('sky-ibl'), ktx2);
      expect(await reader.readResource('wind-sfx'), wav);
    },
  );
}
