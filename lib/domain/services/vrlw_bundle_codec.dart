import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;

import '../../utils/constants/vr_world_constants.dart';
import '../../utils/vr_world_validator.dart';
import '../models/vr_world_address.dart';
import '../models/vr_world_entity.dart';
import '../models/vr_world_position.dart';
import '../models/vr_world_transform.dart';
import '../models/vrlw_audio_emitter.dart';
import '../models/vrlw_bundle_header.dart';
import '../models/vrlw_bundle_index.dart';
import '../models/vrlw_chunk_index.dart';
import '../models/vrlw_collider_spec.dart';
import '../models/vrlw_environment_spec.dart';
import '../models/vrlw_interaction_spec.dart';
import '../models/vrlw_motion_spec.dart';
import '../models/vrlw_prototype_binding.dart';
import '../models/vrlw_resource_index.dart';
import '../models/vrlw_world_dependency.dart';
import 'vrlw_bounded_output.dart';

typedef _MetadataRecord = ({
  String id,
  String title,
  String revision,
  String license,
  String gridId,
  double cellSizeMeters,
  Set<String> prototypeIds,
  Map<String, Object?> origin,
});

typedef _PlacementRecord = ({
  String id,
  String prototypeId,
  double x,
  double y,
  double z,
  double yawRadians,
  double scale,
});

/// Experimental data-only regional world format; this never executes Dart,
/// loads plugins, or instantiates unregistered prototypes.
abstract final class VrlwBundleCodec {
  static const headerSize = VrWorldConstants.vrlwHeaderSize;
  static const maxManifestBytes = VrWorldConstants.vrlwMaxManifestBytes;
  static const maxChunks = VrWorldConstants.vrlwMaxChunks;
  static const maxPackedChunkBytes = VrWorldConstants.vrlwMaxPackedChunkBytes;
  static const maxUnpackedChunkBytes =
      VrWorldConstants.vrlwMaxUnpackedChunkBytes;
  static const maxFileBytes = VrWorldConstants.vrlwMaxFileBytes;
  static const maxTotalUnpackedBytes =
      VrWorldConstants.vrlwMaxTotalUnpackedBytes;
  static const maxEntitiesPerChunk = VrWorldConstants.vrlwMaxEntitiesPerChunk;
  static const maxResources = VrWorldConstants.vrlwMaxResources;
  static const maxResourceBytes = VrWorldConstants.vrlwMaxResourceBytes;
  static const maxTotalResourceBytes =
      VrWorldConstants.vrlwMaxTotalResourceBytes;
  static const maxTextureDimension = VrWorldConstants.vrlwMaxTextureDimension;
  static const maxCompressedTextureDimension =
      VrWorldConstants.vrlwMaxCompressedTextureDimension;
  static const maxAudioEmitters = VrWorldConstants.vrlwMaxAudioEmitters;
  static const maxMotions = VrWorldConstants.vrlwMaxMotions;
  static const maxInteractions = VrWorldConstants.vrlwMaxInteractions;
  static const maxDependencies = VrWorldConstants.vrlwMaxDependencies;
  static const _magic = VrWorldConstants.vrlwMagic;

  /// Shared PNG preflight for standalone textures and embedded GLB images.
  /// The complete profile checks chunks/CRCs and bounded scanline inflation,
  /// admitting only static, non-interlaced RGB8/RGBA8. Pixel reconstruction and
  /// color conversion still belong to the renderer, not this container codec.
  static ({int width, int height}) validatePngTextureBytes(
    Uint8List bytes, {
    int? width,
    int? height,
    bool requireComplete = false,
    int maxDimension = maxCompressedTextureDimension,
  }) => _validatePngTextureBytes(
    bytes,
    width,
    height,
    requireComplete: requireComplete,
    maxDimension: maxDimension,
  );

  /// Parses exactly the fixed prefix. A transport must separately verify the
  /// actual resource length equals [VrlwBundleHeader.totalLength].
  static VrlwBundleHeader parseHeader(List<int> bytes) {
    if (bytes.length != headerSize) _fail('Expected exactly 16 header bytes.');
    final data = Uint8List.fromList(bytes);
    if (ascii.decode(data.sublist(0, 8), allowInvalid: true) != _magic) {
      _fail('Unsupported VRLW magic or format version.');
    }
    final view = ByteData.sublistView(data);
    final manifestLength = view.getUint32(8, Endian.little);
    final payloadLength = view.getUint32(12, Endian.little);
    if (manifestLength < 2 || manifestLength > maxManifestBytes) {
      _fail('Index exceeds its byte budget.');
    }
    final header = VrlwBundleHeader(manifestLength, payloadLength);
    if (header.totalLength > maxFileBytes) _fail('Bundle exceeds file budget.');
    return header;
  }

  /// Parses only the bounded front index. No region data is expanded here.
  static VrlwBundleIndex parseIndex(
    VrlwBundleHeader header,
    List<int> manifestBytes,
  ) {
    if (manifestBytes.length != header.manifestLength) {
      _fail('Index byte length does not match its header.');
    }
    final document = _jsonObject(manifestBytes);
    _keys(document, {..._metadataKeys, 'chunks', ..._resourceKeys}, 'index');
    final metadata = _parseMetadata(document);
    final rawChunks = _list(document['chunks'], 'chunks', maxChunks);
    final cells = <(int, int)>{};
    final chunks = <VrlwChunkIndex>[];
    var nextOffset = 0;
    var decodedTotal = 0;
    for (final raw in rawChunks) {
      final map = _object(raw, 'chunk');
      _keys(map, {
        'x',
        'z',
        'offset',
        'packedBytes',
        'unpackedBytes',
        'codec',
        'sha256',
      }, 'chunk');
      final (x, z) = _cell(map, metadata.cellSizeMeters);
      if (!cells.add((x, z))) _fail('Duplicate region ($x,$z).');
      final offset = _integer(map['offset'], 'offset', 0, maxFileBytes);
      final packed = _integer(
        map['packedBytes'],
        'packedBytes',
        1,
        maxPackedChunkBytes,
      );
      final unpacked = _integer(
        map['unpackedBytes'],
        'unpackedBytes',
        1,
        maxUnpackedChunkBytes,
      );
      final codec = map['codec'];
      if (codec != 'store' && codec != 'deflate') {
        _fail('Unsupported chunk codec.');
      }
      if (codec == 'store' && packed != unpacked) {
        _fail('Stored chunk lengths must match.');
      }
      final digest = map['sha256'];
      if (digest is! String ||
          !RegExp(VrWorldConstants.sha256Pattern).hasMatch(digest)) {
        _fail('Invalid chunk SHA-256.');
      }
      if (offset != nextOffset) _fail('Chunks must be contiguous and ordered.');
      nextOffset += packed;
      decodedTotal += unpacked;
      if (nextOffset > header.packedPayloadLength ||
          decodedTotal > maxTotalUnpackedBytes) {
        _fail('Region data exceeds the bundle budget.');
      }
      chunks.add(
        VrlwChunkIndex(
          x: x,
          z: z,
          offset: offset,
          packedBytes: packed,
          unpackedBytes: unpacked,
          codec: codec as String,
          sha256: digest,
        ),
      );
    }
    final resources = <VrlwResourceIndex>[];
    final resourceIds = <String>{};
    var resourceTotal = 0;
    for (final raw in _optionalList(document, 'resources', maxResources)) {
      final map = _object(raw, 'resource');
      _keys(map, {
        'id',
        'type',
        'offset',
        'packedBytes',
        'unpackedBytes',
        'codec',
        'sha256',
        'width',
        'height',
      }, 'resource');
      final id = _identifier(map['id'], 'resource id');
      if (!resourceIds.add(id)) _fail('Duplicate resource $id.');
      final type = _resourceType(map['type']);
      final offset = _integer(
        map['offset'],
        'resource offset',
        0,
        maxFileBytes,
      );
      final packed = _integer(
        map['packedBytes'],
        'resource packedBytes',
        1,
        maxResourceBytes,
      );
      final unpacked = _integer(
        map['unpackedBytes'],
        'resource unpackedBytes',
        1,
        maxResourceBytes,
      );
      final codec = map['codec'];
      if (codec != 'store' && codec != 'deflate') {
        _fail('Unsupported resource codec.');
      }
      if (codec == 'store' && packed != unpacked) {
        _fail('Stored resource lengths must match.');
      }
      final digest = map['sha256'];
      if (digest is! String ||
          !RegExp(VrWorldConstants.sha256Pattern).hasMatch(digest)) {
        _fail('Invalid resource SHA-256.');
      }
      final (width, height) = _resourceDimensions(map, type, unpacked);
      if (offset != nextOffset) {
        _fail('Resources must follow regions contiguously.');
      }
      nextOffset += packed;
      resourceTotal += unpacked;
      if (nextOffset > header.packedPayloadLength ||
          resourceTotal > maxTotalResourceBytes ||
          decodedTotal + resourceTotal > maxTotalUnpackedBytes) {
        _fail('Resources exceed the bundle budget.');
      }
      resources.add(
        VrlwResourceIndex(
          id: id,
          type: type,
          offset: offset,
          packedBytes: packed,
          unpackedBytes: unpacked,
          codec: codec as String,
          sha256: digest,
          width: width,
          height: height,
        ),
      );
    }
    final bindings = _bindings(document, metadata.prototypeIds, resources);
    final environment = _environment(document, resources);
    final audioEmitters = _audioEmitters(document, resources);
    final motions = _motions(document, bindings);
    final interactions = _interactions(
      document,
      motions,
      audioEmitters,
      cells,
      metadata.cellSizeMeters,
    );
    final dependencies = _dependencies(document, metadata.id);
    if (nextOffset != header.packedPayloadLength) {
      _fail('Unindexed or missing payload bytes.');
    }
    return VrlwBundleIndex(
      header: header,
      id: metadata.id,
      title: metadata.title,
      revision: metadata.revision,
      license: metadata.license,
      gridId: metadata.gridId,
      cellSizeMeters: metadata.cellSizeMeters,
      prototypeIds: metadata.prototypeIds,
      origin: metadata.origin,
      indexSha256: crypto.sha256.convert(manifestBytes).toString(),
      chunks: chunks,
      resources: resources,
      prototypeBindings: bindings,
      environment: environment,
      audioEmitters: audioEmitters,
      motions: motions,
      interactions: interactions,
      dependencies: dependencies,
    );
  }

  /// Decodes one resource with integrity, bounded expansion and envelope checks.
  static Uint8List decodeResource(
    VrlwBundleIndex index,
    VrlwResourceIndex resource,
    List<int> packedBytes,
  ) {
    if (!identical(index.resourceAt(resource.id), resource)) {
      _fail('Resource does not belong to this bundle index.');
    }
    final bytes = _decodeResourceBlock(resource, packedBytes);
    _validateResourceBytes(
      resource.type,
      bytes,
      resource.width,
      resource.height,
    );
    return bytes;
  }

  /// Checks a selected compressed region before decoding it for the host world.
  static List<VrWorldEntity> decodeChunk(
    VrlwBundleIndex index,
    VrlwChunkIndex chunk,
    List<int> packedBytes, {
    required VrWorldAddress world,
    required Set<String> registeredPrototypeIds,
  }) {
    if (!identical(index.chunkAt(chunk.x, chunk.z), chunk)) {
      _fail('Chunk does not belong to this bundle index.');
    }
    if (packedBytes.length != chunk.packedBytes) {
      _fail('Packed region byte length mismatch.');
    }
    if (crypto.sha256.convert(packedBytes).toString() != chunk.sha256) {
      _fail('Region integrity check failed.');
    }
    final Uint8List bytes;
    if (chunk.codec == 'store') {
      bytes = Uint8List.fromList(packedBytes);
    } else {
      final output = VrlwBoundedOutput(chunk.unpackedBytes);
      final input = InputMemoryStream([...packedBytes, 0, 0, 0, 0, 0, 0]);
      try {
        Inflate.stream(input, output: output);
      } catch (_) {
        _fail('Invalid or over-budget DEFLATE region.');
      }
      if (input.position != packedBytes.length ||
          output.length != chunk.unpackedBytes) {
        _fail('Compressed region is truncated or has trailing data.');
      }
      bytes = output.getBytes();
    }
    if (bytes.length != chunk.unpackedBytes) {
      _fail('Expanded region byte length mismatch.');
    }
    final document = _jsonObject(bytes);
    _keys(document, {'entities'}, 'region payload');
    final placements = _placements(
      document['entities'],
      cellSizeMeters: index.cellSizeMeters,
      prototypeIds: index.prototypeIds,
    );
    return List.unmodifiable(
      placements.map((placement) {
        if (!registeredPrototypeIds.contains(placement.prototypeId)) {
          _fail(
            'Prototype ${placement.prototypeId} is not registered by host.',
          );
        }
        return VrWorldEntity(
          id: placement.id,
          prototypeId: placement.prototypeId,
          world: world,
          transform: VrWorldTransform(
            position: VrWorldPosition(
              chunk.x * index.cellSizeMeters + placement.x,
              placement.y,
              chunk.z * index.cellSizeMeters + placement.z,
            ),
            yawRadians: placement.yawRadians,
            scale: placement.scale,
          ),
        );
      }),
    );
  }

  /// Compiles a bounded authoring document to an indexed data container.
  static Uint8List encode(Map<String, Object?> source, {bool compress = true}) {
    _keys(source, {..._metadataKeys, 'regions', ..._resourceKeys}, 'source');
    final metadata = _parseMetadata(source);
    final regions = _list(source['regions'], 'regions', maxChunks);
    final chunks = <VrlwChunkIndex>[];
    final payload = BytesBuilder(copy: false);
    final ids = <String>{};
    final cells = <(int, int)>{};
    var unpackedTotal = 0;
    for (final region in regions) {
      final raw = _object(region, 'region');
      _keys(raw, {'x', 'z', 'entities'}, 'region');
      final (x, z) = _cell(raw, metadata.cellSizeMeters);
      if (!cells.add((x, z))) _fail('Duplicate region ($x,$z).');
      final placements = _placements(
        raw['entities'],
        cellSizeMeters: metadata.cellSizeMeters,
        prototypeIds: metadata.prototypeIds,
      );
      for (final placement in placements) {
        if (!ids.add(placement.id)) _fail('Duplicate entity ${placement.id}.');
      }
      final unpacked = utf8.encode(
        jsonEncode({
          'entities': placements
              .map(
                (placement) => {
                  'id': placement.id,
                  'prototypeId': placement.prototypeId,
                  'x': placement.x,
                  'y': placement.y,
                  'z': placement.z,
                  'yawRadians': placement.yawRadians,
                  'scale': placement.scale,
                },
              )
              .toList(),
        }),
      );
      if (unpacked.length > maxUnpackedChunkBytes) {
        _fail('Region exceeds expanded byte budget.');
      }
      unpackedTotal += unpacked.length;
      if (unpackedTotal > maxTotalUnpackedBytes) {
        _fail('Bundle exceeds total expanded byte budget.');
      }
      final compressed = compress ? Deflate(unpacked).getBytes() : unpacked;
      final useDeflate = compress && compressed.length < unpacked.length;
      final packed = useDeflate ? compressed : unpacked;
      if (packed.length > maxPackedChunkBytes) {
        _fail('Region exceeds packed byte budget.');
      }
      chunks.add(
        VrlwChunkIndex(
          x: x,
          z: z,
          offset: payload.length,
          packedBytes: packed.length,
          unpackedBytes: unpacked.length,
          codec: useDeflate ? 'deflate' : 'store',
          sha256: crypto.sha256.convert(packed).toString(),
        ),
      );
      if (payload.length + packed.length > maxFileBytes - headerSize) {
        _fail('Bundle exceeds file budget.');
      }
      payload.add(packed);
    }
    final resources = <VrlwResourceIndex>[];
    final resourceIds = <String>{};
    var resourceTotal = 0;
    for (final raw in _optionalList(source, 'resources', maxResources)) {
      final map = _object(raw, 'resource source');
      _keys(map, {'id', 'type', 'data', 'width', 'height'}, 'resource source');
      final id = _identifier(map['id'], 'resource id');
      if (!resourceIds.add(id)) _fail('Duplicate resource $id.');
      final type = _resourceType(map['type']);
      final encoded = map['data'];
      if (encoded is! String ||
          encoded.length > ((maxResourceBytes + 2) ~/ 3) * 4) {
        _fail('Resource base64 exceeds its byte budget.');
      }
      Uint8List bytes;
      try {
        bytes = base64.decode(encoded);
      } on FormatException {
        _fail('Invalid resource base64.');
      }
      if (bytes.isEmpty || bytes.length > maxResourceBytes) {
        _fail('Resource exceeds its byte budget.');
      }
      final (width, height) = _resourceDimensions(map, type, bytes.length);
      _validateResourceBytes(type, bytes, width, height);
      resourceTotal += bytes.length;
      if (resourceTotal > maxTotalResourceBytes ||
          unpackedTotal + resourceTotal > maxTotalUnpackedBytes) {
        _fail('Resources exceed the bundle budget.');
      }
      final compressed = compress ? Deflate(bytes).getBytes() : bytes;
      final useDeflate = compress && compressed.length < bytes.length;
      final packed = useDeflate ? compressed : bytes;
      resources.add(
        VrlwResourceIndex(
          id: id,
          type: type,
          offset: payload.length,
          packedBytes: packed.length,
          unpackedBytes: bytes.length,
          codec: useDeflate ? 'deflate' : 'store',
          sha256: crypto.sha256.convert(packed).toString(),
          width: width,
          height: height,
        ),
      );
      if (payload.length + packed.length > maxFileBytes - headerSize) {
        _fail('Bundle exceeds file budget.');
      }
      payload.add(packed);
    }
    final bindings = _bindings(source, metadata.prototypeIds, resources);
    final environment = _environment(source, resources);
    final audioEmitters = _audioEmitters(source, resources);
    final motions = _motions(source, bindings);
    final interactions = _interactions(
      source,
      motions,
      audioEmitters,
      cells,
      metadata.cellSizeMeters,
    );
    final dependencies = _dependencies(source, metadata.id);
    final manifest = utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'id': metadata.id,
        'title': metadata.title,
        'revision': metadata.revision,
        'license': metadata.license,
        'gridId': metadata.gridId,
        'cellSizeMeters': metadata.cellSizeMeters,
        'prototypes': metadata.prototypeIds.toList(),
        'origin': metadata.origin,
        'chunks': chunks.map((chunk) => chunk.toJson()).toList(),
        if (source.containsKey('resources'))
          'resources': resources.map((resource) => resource.toJson()).toList(),
        if (source.containsKey('prototypeBindings'))
          'prototypeBindings': bindings
              .map((binding) => binding.toJson())
              .toList(),
        if (environment != null) 'environment': environment.toJson(),
        if (source.containsKey('audioEmitters'))
          'audioEmitters': audioEmitters.map((e) => e.toJson()).toList(),
        if (motions.isNotEmpty)
          'motions': motions.map((motion) => motion.toJson()).toList(),
        if (interactions.isNotEmpty)
          'interactions': interactions.map((item) => item.toJson()).toList(),
        if (source.containsKey('dependencies'))
          'dependencies': dependencies.map((d) => d.toJson()).toList(),
      }),
    );
    if (manifest.length > maxManifestBytes ||
        headerSize + manifest.length + payload.length > maxFileBytes) {
      _fail('Bundle exceeds index or file budget.');
    }
    final header = Uint8List(headerSize)..setRange(0, 8, ascii.encode(_magic));
    ByteData.sublistView(header)
      ..setUint32(8, manifest.length, Endian.little)
      ..setUint32(12, payload.length, Endian.little);
    return (BytesBuilder(copy: false)
          ..add(header)
          ..add(manifest)
          ..add(payload.takeBytes()))
        .takeBytes();
  }
}

const _resourceKeys = {
  'resources',
  'prototypeBindings',
  'environment',
  'audioEmitters',
  'motions',
  'interactions',
  'dependencies',
};

const _supportedResourceTypes = {
  'model.glb',
  'texture.rgba8',
  'texture.png',
  'texture.jpeg',
  'texture.ktx2',
  'environment.ktx2',
  'audio.wav',
  'audio.ogg',
  'audio.mp3',
};

bool _isTextureResourceType(String? type) =>
    type == 'texture.rgba8' ||
    type == 'texture.png' ||
    type == 'texture.jpeg' ||
    type == 'texture.ktx2';

bool _isAudioResourceType(String? type) =>
    type == 'audio.wav' || type == 'audio.ogg' || type == 'audio.mp3';

List<Object?> _optionalList(
  Map<String, Object?> map,
  String name,
  int maximum,
) => map.containsKey(name) ? _list(map[name], name, maximum) : const [];

String _resourceType(Object? value) {
  if (value is! String || !_supportedResourceTypes.contains(value)) {
    _fail('Unsupported resource type.');
  }
  return value;
}

(int?, int?) _resourceDimensions(
  Map<String, Object?> map,
  String type,
  int bytes,
) {
  if (type == 'model.glb') {
    if (map.containsKey('width') || map.containsKey('height')) {
      _fail('Model resources cannot declare texture dimensions.');
    }
    if (bytes < 32) _fail('GLB resource is too short.');
    return (null, null);
  }
  if (type == 'environment.ktx2' || _isAudioResourceType(type)) {
    if (map.containsKey('width') || map.containsKey('height')) {
      _fail('Non-2D texture resources cannot declare width/height.');
    }
    return (null, null);
  }
  if (type == 'texture.rgba8') {
    final width = _integer(
      map['width'],
      'texture width',
      1,
      VrlwBundleCodec.maxTextureDimension,
    );
    final height = _integer(
      map['height'],
      'texture height',
      1,
      VrlwBundleCodec.maxTextureDimension,
    );
    if (bytes != width * height * 4) {
      _fail('RGBA8 resource length does not match dimensions.');
    }
    return (width, height);
  }
  final hasWidth = map.containsKey('width');
  final hasHeight = map.containsKey('height');
  if (hasWidth != hasHeight) {
    _fail('Compressed textures must declare both width and height or neither.');
  }
  if (!hasWidth) return (null, null);
  final width = _integer(
    map['width'],
    'texture width',
    1,
    VrlwBundleCodec.maxCompressedTextureDimension,
  );
  final height = _integer(
    map['height'],
    'texture height',
    1,
    VrlwBundleCodec.maxCompressedTextureDimension,
  );
  return (width, height);
}

List<VrlwPrototypeBinding> _bindings(
  Map<String, Object?> document,
  Set<String> prototypes,
  List<VrlwResourceIndex> resources,
) {
  final byId = {for (final resource in resources) resource.id: resource};
  final seen = <String>{};
  final result = <VrlwPrototypeBinding>[];
  String? optionalTexture(Map<String, Object?> map, String key) {
    if (!map.containsKey(key)) return null;
    final id = _identifier(map[key], key);
    if (!_isTextureResourceType(byId[id]?.type)) {
      _fail('$key binding requires a texture resource.');
    }
    return id;
  }

  for (final raw in _optionalList(document, 'prototypeBindings', 1024)) {
    final map = _object(raw, 'prototype binding');
    _keys(map, {
      'prototypeId',
      'model',
      'baseColorTexture',
      'normalTexture',
      'metallicRoughnessTexture',
      'emissiveTexture',
      'occlusionTexture',
      'audio',
      'collider',
      'castsShadows',
    }, 'prototype binding');
    final prototype = _identifier(map['prototypeId'], 'bound prototype');
    if (!prototypes.contains(prototype) || !seen.add(prototype)) {
      _fail('Undeclared or duplicate prototype binding.');
    }
    final model = _identifier(map['model'], 'model resource');
    if (byId[model]?.type != 'model.glb') {
      _fail('Binding requires a model.glb resource.');
    }
    final baseColorTexture = optionalTexture(map, 'baseColorTexture');
    final normalTexture = optionalTexture(map, 'normalTexture');
    final metallicRoughnessTexture = optionalTexture(
      map,
      'metallicRoughnessTexture',
    );
    final emissiveTexture = optionalTexture(map, 'emissiveTexture');
    final occlusionTexture = optionalTexture(map, 'occlusionTexture');
    String? audio;
    if (map.containsKey('audio')) {
      audio = _identifier(map['audio'], 'audio resource');
      if (!_isAudioResourceType(byId[audio]?.type)) {
        _fail('Audio binding requires an audio.* resource.');
      }
    }
    VrlwColliderSpec? collider;
    if (map.containsKey('collider')) {
      collider = _parseCollider(map['collider']);
    }
    bool? castsShadows;
    if (map.containsKey('castsShadows')) {
      final rawShadows = map['castsShadows'];
      if (rawShadows is! bool) _fail('castsShadows must be a boolean.');
      castsShadows = rawShadows;
    }
    result.add(
      VrlwPrototypeBinding(
        prototypeId: prototype,
        model: model,
        baseColorTexture: baseColorTexture,
        normalTexture: normalTexture,
        metallicRoughnessTexture: metallicRoughnessTexture,
        emissiveTexture: emissiveTexture,
        occlusionTexture: occlusionTexture,
        audio: audio,
        collider: collider,
        castsShadows: castsShadows,
      ),
    );
  }
  return result;
}

VrlwColliderSpec _parseCollider(Object? raw) {
  final map = _object(raw, 'collider');
  _keys(map, {
    'shape',
    'halfExtents',
    'radius',
    'height',
    'offset',
  }, 'collider');
  final shape = map['shape'];
  if (shape is! String ||
      !{'box', 'sphere', 'cylinder', 'capsule'}.contains(shape)) {
    _fail('Unsupported collider shape.');
  }
  final offset = map.containsKey('offset')
      ? _vec3(map['offset'], 'collider offset', -1000, 1000)
      : const <double>[0, 0, 0];
  if (shape == 'box') {
    if (map.containsKey('radius') || map.containsKey('height')) {
      _fail('Box collider cannot declare radius or height.');
    }
    final halfExtents = _vec3(
      map['halfExtents'],
      'collider halfExtents',
      0.001,
      1000,
    );
    return VrlwColliderSpec(
      shape: shape,
      halfExtents: List.unmodifiable(halfExtents),
      offset: List.unmodifiable(offset),
    );
  }
  if (map.containsKey('halfExtents')) {
    _fail('Non-box collider cannot declare halfExtents.');
  }
  final radius = _number(map['radius'], 'collider radius', 0.001, 1000);
  if (shape == 'sphere') {
    if (map.containsKey('height')) {
      _fail('Sphere collider cannot declare height.');
    }
    return VrlwColliderSpec(
      shape: shape,
      radius: radius,
      offset: List.unmodifiable(offset),
    );
  }
  final height = _number(map['height'], 'collider height', 0.001, 1000);
  return VrlwColliderSpec(
    shape: shape,
    radius: radius,
    height: height,
    offset: List.unmodifiable(offset),
  );
}

VrlwEnvironmentSpec? _environment(
  Map<String, Object?> document,
  List<VrlwResourceIndex> resources,
) {
  if (!document.containsKey('environment')) return null;
  final map = _object(document['environment'], 'environment');
  _keys(map, {
    'environmentResource',
    'skyboxResource',
    'environmentIntensity',
    'exposure',
    'sunDirection',
    'sunColor',
    'sunIntensity',
    'castsShadows',
  }, 'environment');
  final byId = {for (final resource in resources) resource.id: resource};
  String? environmentResource;
  if (map.containsKey('environmentResource')) {
    environmentResource = _identifier(
      map['environmentResource'],
      'environmentResource',
    );
    if (byId[environmentResource]?.type != 'environment.ktx2') {
      _fail('environmentResource requires an environment.ktx2 resource.');
    }
  }
  String? skyboxResource;
  if (map.containsKey('skyboxResource')) {
    skyboxResource = _identifier(map['skyboxResource'], 'skyboxResource');
    final type = byId[skyboxResource]?.type;
    if (type != 'environment.ktx2' && !_isTextureResourceType(type)) {
      _fail('skyboxResource requires an environment.ktx2 or texture resource.');
    }
  }
  final environmentIntensity = map.containsKey('environmentIntensity')
      ? _number(map['environmentIntensity'], 'environmentIntensity', 0, 10)
      : null;
  final exposure = map.containsKey('exposure')
      ? _number(map['exposure'], 'exposure', 0.05, 20)
      : null;
  List<double>? sunDirection;
  if (map.containsKey('sunDirection')) {
    sunDirection = List.unmodifiable(
      _vec3(map['sunDirection'], 'sunDirection', -100, 100),
    );
    final len2 =
        sunDirection[0] * sunDirection[0] +
        sunDirection[1] * sunDirection[1] +
        sunDirection[2] * sunDirection[2];
    if (len2 < 1e-6) _fail('sunDirection must be non-zero.');
  }
  final sunColor = map.containsKey('sunColor')
      ? List<double>.unmodifiable(_vec3(map['sunColor'], 'sunColor', 0, 10))
      : null;
  final sunIntensity = map.containsKey('sunIntensity')
      ? _number(map['sunIntensity'], 'sunIntensity', 0, 20)
      : null;
  bool? castsShadows;
  if (map.containsKey('castsShadows')) {
    if (map['castsShadows'] is! bool) {
      _fail('environment castsShadows must be a boolean.');
    }
    castsShadows = map['castsShadows'] as bool;
  }
  return VrlwEnvironmentSpec(
    environmentResource: environmentResource,
    skyboxResource: skyboxResource,
    environmentIntensity: environmentIntensity,
    exposure: exposure,
    sunDirection: sunDirection,
    sunColor: sunColor,
    sunIntensity: sunIntensity,
    castsShadows: castsShadows,
  );
}

List<VrlwAudioEmitter> _audioEmitters(
  Map<String, Object?> document,
  List<VrlwResourceIndex> resources,
) {
  final byId = {for (final resource in resources) resource.id: resource};
  final seen = <String>{};
  final result = <VrlwAudioEmitter>[];
  for (final raw in _optionalList(
    document,
    'audioEmitters',
    VrlwBundleCodec.maxAudioEmitters,
  )) {
    final map = _object(raw, 'audio emitter');
    _keys(map, {
      'id',
      'resource',
      'x',
      'y',
      'z',
      'volume',
      'maxDistance',
      'loop',
    }, 'audio emitter');
    final id = _identifier(map['id'], 'audio emitter id');
    if (!seen.add(id)) _fail('Duplicate audio emitter $id.');
    final resource = _identifier(map['resource'], 'audio emitter resource');
    if (!_isAudioResourceType(byId[resource]?.type)) {
      _fail('Audio emitter requires an audio.* resource.');
    }
    final bound = VrWorldPosition.maximumCoordinateMeters;
    final x = _number(map['x'], 'emitter x', -bound, bound);
    final y = _number(map['y'], 'emitter y', -bound, bound);
    final z = _number(map['z'], 'emitter z', -bound, bound);
    final volume = _number(map['volume'] ?? 1.0, 'emitter volume', 0, 1);
    final maxDistance = _number(
      map['maxDistance'] ?? 24.0,
      'emitter maxDistance',
      0.1,
      500,
    );
    final loop = map['loop'] ?? true;
    if (loop is! bool) _fail('Audio emitter loop must be a boolean.');
    result.add(
      VrlwAudioEmitter(
        id: id,
        resource: resource,
        x: x,
        y: y,
        z: z,
        volume: volume,
        maxDistance: maxDistance,
        loop: loop,
      ),
    );
  }
  return result;
}

List<VrlwMotionSpec> _motions(
  Map<String, Object?> document,
  List<VrlwPrototypeBinding> bindings,
) {
  final boundPrototypes = bindings
      .map((binding) => binding.prototypeId)
      .toSet();
  final ids = <String>{};
  final targets = <(String, String)>{};
  final result = <VrlwMotionSpec>[];
  for (final raw in _optionalList(
    document,
    'motions',
    VrlwBundleCodec.maxMotions,
  )) {
    final map = _object(raw, 'motion');
    _keys(map, {
      'id',
      'prototypeId',
      'node',
      'kind',
      'axis',
      'pivot',
      'periodSeconds',
      'amplitude',
      'rangeMeters',
      'initiallyEnabled',
    }, 'motion');
    final id = _identifier(map['id'], 'motion id');
    if (!ids.add(id)) _fail('Duplicate motion id.');
    final prototype = _identifier(map['prototypeId'], 'motion prototypeId');
    if (!boundPrototypes.contains(prototype)) {
      _fail('Motion requires a bound model prototype.');
    }
    final node = _identifier(map['node'], 'motion node');
    if (!targets.add((prototype, node))) {
      _fail('A model node cannot have multiple motion specifications.');
    }
    final kind = map['kind'];
    if (kind != 'spin' && kind != 'bob') _fail('Unsupported motion kind.');
    final axis = map['axis'];
    if (axis != 'x' && axis != 'y' && axis != 'z') {
      _fail('Unsupported motion axis.');
    }
    final pivot = map.containsKey('pivot')
        ? _vec3(map['pivot'], 'motion pivot', -32, 32)
        : const <double>[0, 0, 0];
    final period = _number(
      map['periodSeconds'],
      'motion periodSeconds',
      2,
      120,
    );
    double? amplitude;
    if (kind == 'bob') {
      amplitude = _number(map['amplitude'], 'motion amplitude', 0.001, 0.5);
    } else if (map.containsKey('amplitude')) {
      _fail('Spin motion cannot declare amplitude.');
    }
    final range = _number(
      map.containsKey('rangeMeters') ? map['rangeMeters'] : 32,
      'motion rangeMeters',
      4,
      48,
    );
    final enabled = map.containsKey('initiallyEnabled')
        ? map['initiallyEnabled']
        : true;
    if (enabled is! bool) _fail('Motion initiallyEnabled must be a boolean.');
    result.add(
      VrlwMotionSpec(
        id: id,
        prototypeId: prototype,
        node: node,
        kind: kind as String,
        axis: axis as String,
        pivot: pivot,
        periodSeconds: period,
        amplitude: amplitude,
        rangeMeters: range,
        initiallyEnabled: enabled,
      ),
    );
  }
  return result;
}

List<VrlwInteractionSpec> _interactions(
  Map<String, Object?> document,
  List<VrlwMotionSpec> motions,
  List<VrlwAudioEmitter> emitters,
  Set<(int, int)> cells,
  double cellSize,
) {
  final motionIds = motions.map((motion) => motion.id).toSet();
  final emitterIds = emitters.map((emitter) => emitter.id).toSet();
  final ids = <String>{};
  final result = <VrlwInteractionSpec>[];
  for (final raw in _optionalList(
    document,
    'interactions',
    VrlwBundleCodec.maxInteractions,
  )) {
    final map = _object(raw, 'interaction');
    _keys(map, {
      'id',
      'label',
      'position',
      'maxDistance',
      'action',
      'target',
    }, 'interaction');
    final id = _identifier(map['id'], 'interaction id');
    if (!ids.add(id)) _fail('Duplicate interaction id.');
    final label = _text(map['label'], 'interaction label', 80);
    final bound = VrWorldPosition.maximumCoordinateMeters;
    final position = _vec3(
      map['position'],
      'interaction position',
      -bound,
      bound,
    );
    final cell = (
      (position[0] / cellSize).floor(),
      (position[2] / cellSize).floor(),
    );
    if (!cells.contains(cell)) {
      _fail('Interaction must lie inside an indexed region.');
    }
    final distance = _number(
      map.containsKey('maxDistance') ? map['maxDistance'] : 3,
      'interaction maxDistance',
      0.25,
      4,
    );
    final action = map['action'];
    final target = _identifier(map['target'], 'interaction target');
    if (action == 'toggleMotion') {
      if (!motionIds.contains(target)) {
        _fail('Unknown interaction motion target.');
      }
    } else if (action == 'toggleAudio') {
      if (!emitterIds.contains(target)) {
        _fail('Unknown interaction audio target.');
      }
    } else {
      _fail('Unsupported interaction action.');
    }
    result.add(
      VrlwInteractionSpec(
        id: id,
        label: label,
        position: position,
        maxDistance: distance,
        action: action as String,
        target: target,
      ),
    );
  }
  return result;
}

List<VrlwWorldDependency> _dependencies(
  Map<String, Object?> document,
  String selfWorldId,
) {
  final aliases = <String>{};
  final ids = <String>{};
  final result = <VrlwWorldDependency>[];
  for (final raw in _optionalList(
    document,
    'dependencies',
    VrlwBundleCodec.maxDependencies,
  )) {
    final map = _object(raw, 'dependency');
    _keys(map, {'alias', 'id', 'revision', 'indexSha256', 'url'}, 'dependency');
    final alias = _identifier(map['alias'], 'dependency alias');
    if (!aliases.add(alias)) _fail('Duplicate dependency alias $alias.');
    final id = _identifier(map['id'], 'dependency id');
    if (id == selfWorldId || !ids.add(id)) {
      _fail('Self or duplicate dependency world id $id.');
    }
    final revision = _identifier(map['revision'], 'dependency revision');
    final digest = map['indexSha256'];
    if (digest is! String ||
        !RegExp(VrWorldConstants.sha256Pattern).hasMatch(digest)) {
      _fail('Invalid dependency indexSha256.');
    }
    String? url;
    if (map.containsKey('url')) {
      final rawUrl = _text(map['url'], 'dependency url', 512);
      final parsed = Uri.tryParse(rawUrl);
      if (parsed == null ||
          parsed.scheme != 'https' ||
          parsed.host.isEmpty ||
          parsed.userInfo.isNotEmpty) {
        _fail('Dependency url must be a valid https:// URI.');
      }
      url = rawUrl;
    }
    result.add(
      VrlwWorldDependency(
        alias: alias,
        id: id,
        revision: revision,
        indexSha256: digest,
        url: url,
      ),
    );
  }
  return result;
}

List<double> _vec3(Object? value, String name, double min, double max) {
  final list = _list(value, name, 3);
  if (list.length != 3) _fail('$name must have exactly 3 numbers.');
  return [for (var i = 0; i < 3; i++) _number(list[i], '$name[$i]', min, max)];
}

Uint8List _decodeResourceBlock(VrlwResourceIndex resource, List<int> packed) {
  if (packed.length != resource.packedBytes ||
      crypto.sha256.convert(packed).toString() != resource.sha256) {
    _fail('Resource integrity or packed length check failed.');
  }
  if (resource.codec == 'store') return Uint8List.fromList(packed);
  final output = VrlwBoundedOutput(resource.unpackedBytes);
  final input = InputMemoryStream([...packed, 0, 0, 0, 0, 0, 0]);
  try {
    Inflate.stream(input, output: output);
  } catch (_) {
    _fail('Invalid or over-budget DEFLATE resource.');
  }
  if (input.position != packed.length ||
      output.length != resource.unpackedBytes) {
    _fail('Compressed resource is truncated or has trailing data.');
  }
  return output.getBytes();
}

const _pngSignature = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const _ktx2Signature = <int>[
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
];

void _validateResourceBytes(
  String type,
  Uint8List bytes,
  int? width,
  int? height,
) {
  if (type == 'texture.rgba8') {
    if (bytes.length != width! * height! * 4) {
      _fail('Invalid RGBA8 resource bytes.');
    }
    return;
  }
  if (type == 'texture.png') {
    VrlwBundleCodec.validatePngTextureBytes(
      bytes,
      width: width,
      height: height,
    );
    return;
  }
  if (type == 'texture.jpeg') {
    if (bytes.length < 16 ||
        bytes[0] != 0xff ||
        bytes[1] != 0xd8 ||
        bytes[bytes.length - 2] != 0xff ||
        bytes[bytes.length - 1] != 0xd9) {
      _fail('Invalid JPEG resource envelope.');
    }
    return;
  }
  if (type == 'texture.ktx2' || type == 'environment.ktx2') {
    if (bytes.length < 80) _fail('Truncated KTX2 resource.');
    for (var i = 0; i < _ktx2Signature.length; i++) {
      if (bytes[i] != _ktx2Signature[i]) _fail('Invalid KTX2 identifier.');
    }
    final data = ByteData.sublistView(bytes);
    final ktxW = data.getUint32(20, Endian.little);
    final ktxH = data.getUint32(24, Endian.little);
    if (ktxW < 1 ||
        ktxW > VrlwBundleCodec.maxCompressedTextureDimension ||
        ktxH < 1 ||
        ktxH > VrlwBundleCodec.maxCompressedTextureDimension) {
      _fail('KTX2 dimensions exceed portable texture budget.');
    }
    if ((width != null && ktxW != width) ||
        (height != null && ktxH != height)) {
      _fail('KTX2 header dimensions do not match declared width/height.');
    }
    return;
  }
  if (type == 'audio.wav') {
    if (bytes.length < 44) _fail('Truncated WAV audio resource.');
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.little) != 0x46464952 ||
        data.getUint32(8, Endian.little) != 0x45564157) {
      _fail('Invalid RIFF/WAVE header.');
    }
    return;
  }
  if (type == 'audio.ogg') {
    if (bytes.length < 28) _fail('Truncated Ogg audio resource.');
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.little) != 0x5367674f) {
      _fail('Invalid OggS capture pattern.');
    }
    return;
  }
  if (type == 'audio.mp3') {
    if (bytes.length < 16) _fail('Truncated MP3 audio resource.');
    final isId3 = bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33;
    final isSync = bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0;
    if (!isId3 && !isSync) {
      _fail('Invalid MP3 header or frame sync.');
    }
    return;
  }
  if (bytes.length < 32) _fail('Truncated GLB resource.');
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != 0x46546c67 ||
      data.getUint32(4, Endian.little) != 2 ||
      data.getUint32(8, Endian.little) != bytes.length) {
    _fail('Invalid GLB resource header.');
  }
  final jsonBytes = data.getUint32(12, Endian.little);
  final binOffset = 20 + jsonBytes;
  if (jsonBytes < 4 ||
      jsonBytes % 4 != 0 ||
      binOffset + 8 > bytes.length ||
      data.getUint32(16, Endian.little) != 0x4e4f534a) {
    _fail('GLB resource requires an aligned JSON chunk.');
  }
  final binBytes = data.getUint32(binOffset, Endian.little);
  if (binBytes % 4 != 0 ||
      binOffset + 8 + binBytes != bytes.length ||
      data.getUint32(binOffset + 4, Endian.little) != 0x004e4942) {
    _fail('GLB resource requires exactly one trailing BIN chunk.');
  }
}

({int width, int height}) _validatePngTextureBytes(
  Uint8List bytes,
  int? width,
  int? height, {
  required bool requireComplete,
  required int maxDimension,
}) {
  if (bytes.length < 33) _fail('Truncated PNG resource.');
  for (var i = 0; i < _pngSignature.length; i++) {
    if (bytes[i] != _pngSignature[i]) _fail('Invalid PNG signature.');
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(8) != 13 || data.getUint32(12) != 0x49484452) {
    _fail('PNG resource requires an initial IHDR chunk.');
  }
  final pngW = data.getUint32(16), pngH = data.getUint32(20);
  if (maxDimension < 1 ||
      maxDimension > VrlwBundleCodec.maxCompressedTextureDimension ||
      pngW < 1 ||
      pngW > maxDimension ||
      pngW > VrlwBundleCodec.maxCompressedTextureDimension ||
      pngH < 1 ||
      pngH > maxDimension ||
      pngH > VrlwBundleCodec.maxCompressedTextureDimension) {
    _fail('PNG dimensions exceed portable texture budget.');
  }
  if ((width != null && pngW != width) || (height != null && pngH != height)) {
    _fail('PNG IHDR dimensions do not match declared width/height.');
  }
  if (requireComplete) {
    if (bytes[24] != 8 ||
        !const [2, 6].contains(bytes[25]) ||
        bytes[26] != 0 ||
        bytes[27] != 0 ||
        bytes[28] != 0) {
      _fail('Embedded PNG requires non-interlaced RGB8 or RGBA8.');
    }
    var at = 8, chunks = 0;
    var sawData = false, dataEnded = false, ended = false;
    final idat = BytesBuilder(copy: false);
    while (at < bytes.length) {
      if (bytes.length - at < 12) _fail('Truncated PNG chunk.');
      final length = data.getUint32(at), type = data.getUint32(at + 4);
      if (length > bytes.length - at - 12 || ++chunks > 4096) {
        _fail('PNG chunk exceeds its bounds or count budget.');
      }
      final end = at + 8 + length;
      if (getCrc32(Uint8List.sublistView(bytes, at + 4, end)) !=
          data.getUint32(end)) {
        _fail('PNG chunk checksum mismatch.');
      }
      if (chunks == 1) {
        if (type != 0x49484452 || length != 13) _fail('Invalid PNG IHDR.');
      } else if (type == 0x49484452) {
        _fail('Duplicate PNG IHDR.');
      } else if (type == 0x49444154) {
        if (dataEnded || length == 0) _fail('Invalid PNG IDAT sequence.');
        sawData = true;
        idat.add(Uint8List.sublistView(bytes, at + 8, end));
      } else if (type == 0x49454e44) {
        if (!sawData || length != 0 || end + 4 != bytes.length) {
          _fail('Invalid PNG IEND.');
        }
        ended = true;
      } else {
        // Reject APNG and unknown critical chunks before a platform decoder.
        if (type == 0x6163544c ||
            type == 0x6663544c ||
            type == 0x66644154 ||
            (bytes[at + 4] & 0x20) == 0) {
          _fail('Animated or unsupported critical PNG chunk.');
        }
        if (sawData) dataEnded = true;
      }
      at = end + 4;
    }
    if (!ended) _fail('PNG requires complete IDAT and IEND chunks.');
    final compressed = idat.takeBytes();
    if (compressed.length < 6 ||
        (compressed[0] & 0xf) != 8 ||
        (compressed[0] >> 4) > 7 ||
        (compressed[0] * 256 + compressed[1]) % 31 != 0 ||
        (compressed[1] & 0x20) != 0) {
      _fail('PNG requires a complete DEFLATE zlib stream without dictionary.');
    }
    final channels = bytes[25] == 2 ? 3 : 4;
    final rowBytes = 1 + pngW * channels;
    final expected = pngH * rowBytes;
    final raw = Uint8List.sublistView(compressed, 2, compressed.length - 4);
    final padded = Uint8List(raw.length + 6)..setRange(0, raw.length, raw);
    final input = InputMemoryStream(padded);
    final output = VrlwBoundedOutput(expected);
    try {
      Inflate.stream(input, output: output);
    } catch (_) {
      _fail('Invalid or over-budget PNG DEFLATE scanlines.');
    }
    if (input.position != raw.length || output.length != expected) {
      _fail('PNG scanline length mismatch or trailing compressed data.');
    }
    final scanlines = output.getBytes();
    final adler = ByteData.sublistView(
      compressed,
    ).getUint32(compressed.length - 4);
    if (getAdler32(scanlines) != adler) _fail('PNG zlib checksum mismatch.');
    for (var row = 0; row < pngH; row++) {
      if (scanlines[row * rowBytes] > 4) _fail('Invalid PNG scanline filter.');
    }
  }
  return (width: pngW, height: pngH);
}

const _metadataKeys = {
  'schemaVersion',
  'id',
  'title',
  'revision',
  'license',
  'gridId',
  'cellSizeMeters',
  'prototypes',
  'origin',
};

_MetadataRecord _parseMetadata(Map<String, Object?> map) {
  if (map['schemaVersion'] is! int || map['schemaVersion'] != 1) {
    _fail('Unsupported world schema version.');
  }
  final prototypes = <String>{};
  for (final raw in _list(map['prototypes'], 'prototypes', 1024)) {
    final id = _identifier(raw, 'prototype');
    if (!prototypes.add(id)) _fail('Duplicate prototype declaration.');
  }
  return (
    id: _identifier(map['id'], 'id'),
    title: _text(map['title'], 'title', 160),
    revision: _identifier(map['revision'], 'revision'),
    license: _text(map['license'], 'license', 2048),
    gridId: _identifier(map['gridId'], 'gridId'),
    cellSizeMeters: _number(
      map['cellSizeMeters'],
      'cellSizeMeters',
      VrWorldConstants.minCellSizeMeters,
      VrWorldPosition.maximumCoordinateMeters,
    ),
    prototypeIds: Set.unmodifiable(prototypes),
    origin: _origin(map['origin']),
  );
}

Map<String, Object?> _origin(Object? value) {
  if (value == null) return const {'type': 'local'};
  final origin = _object(value, 'origin');
  if (origin['type'] == 'local') {
    _keys(origin, {'type'}, 'origin');
    return const {'type': 'local'};
  }
  if (origin['type'] != 'wgs84-enu') _fail('Unsupported coordinate origin.');
  _keys(origin, {
    'type',
    'latitudeDegrees',
    'longitudeDegrees',
    'ellipsoidalHeightMeters',
  }, 'origin');
  return Map.unmodifiable({
    'type': 'wgs84-enu',
    'latitudeDegrees': _number(origin['latitudeDegrees'], 'latitude', -90, 90),
    'longitudeDegrees': _number(
      origin['longitudeDegrees'],
      'longitude',
      -180,
      180,
    ),
    'ellipsoidalHeightMeters': _number(
      origin['ellipsoidalHeightMeters'],
      'ellipsoidal height',
      -12000,
      1000000,
    ),
  });
}

List<_PlacementRecord> _placements(
  Object? value, {
  required double cellSizeMeters,
  required Set<String> prototypeIds,
}) {
  final result = <_PlacementRecord>[];
  final ids = <String>{};
  for (final raw in _list(
    value,
    'entities',
    VrlwBundleCodec.maxEntitiesPerChunk,
  )) {
    final map = _object(raw, 'entity');
    _keys(map, {
      'id',
      'prototypeId',
      'x',
      'y',
      'z',
      'yawRadians',
      'scale',
    }, 'entity');
    final id = _identifier(map['id'], 'entity id');
    if (!ids.add(id)) _fail('Duplicate entity $id.');
    final prototype = _identifier(map['prototypeId'], 'prototypeId');
    if (!prototypeIds.contains(prototype)) {
      _fail('Undeclared prototype $prototype.');
    }
    final x = _number(map['x'], 'x', 0, cellSizeMeters);
    final z = _number(map['z'], 'z', 0, cellSizeMeters);
    if (x >= cellSizeMeters || z >= cellSizeMeters) {
      _fail('Entity must lie inside its region, excluding the upper edge.');
    }
    final y = _number(
      map['y'],
      'y',
      -VrWorldPosition.maximumCoordinateMeters,
      VrWorldPosition.maximumCoordinateMeters,
    );
    final yaw = _number(map['yawRadians'] ?? 0, 'yawRadians', -1e9, 1e9);
    final scale = _number(
      map['scale'] ?? 1,
      'scale',
      0,
      VrWorldTransform.maximumScale,
    );
    if (scale <= 0) _fail('Entity scale must be positive.');
    result.add((
      id: id,
      prototypeId: prototype,
      x: x,
      y: y,
      z: z,
      yawRadians: yaw,
      scale: scale,
    ));
  }
  return result;
}

(int, int) _cell(Map<String, Object?> map, double cellSize) {
  final x = _integer(map['x'], 'region x', -100000000, 100000000);
  final z = _integer(map['z'], 'region z', -100000000, 100000000);
  final bound = VrWorldPosition.maximumCoordinateMeters;
  for (final cell in [x, z]) {
    if (cell * cellSize < -bound || (cell + 1) * cellSize > bound) {
      _fail('Region extends outside the supported local coordinate frame.');
    }
  }
  return (x, z);
}

Map<String, Object?> _jsonObject(List<int> bytes) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (final byte in bytes) {
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (byte == 92) {
        escaped = true;
      } else if (byte == 34) {
        inString = false;
      }
    } else if (byte == 34) {
      inString = true;
    } else if (byte == 123 || byte == 91) {
      if (++depth > 12) _fail('JSON nesting exceeds world schema budget.');
    } else if (byte == 125 || byte == 93) {
      depth--;
    }
  }
  try {
    return _object(jsonDecode(utf8.decode(bytes)), 'JSON root');
  } on FormatException {
    rethrow;
  } catch (_) {
    _fail('Invalid world JSON.');
  }
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) _fail('$name must be an object.');
  return value;
}

List<Object?> _list(Object? value, String name, int maximum) {
  if (value is! List || value.length > maximum) {
    _fail('$name must be an array with at most $maximum entries.');
  }
  return value.cast<Object?>();
}

void _keys(Map<String, Object?> map, Set<String> allowed, String name) {
  if (map.keys.any((key) => !allowed.contains(key))) {
    _fail('Unsupported $name field.');
  }
}

String _identifier(Object? value, String name) {
  if (value is! String) _fail('$name must be an identifier.');
  try {
    VrWorldValidator.validateIdentifier(value, name);
  } on ArgumentError {
    _fail('Invalid $name identifier.');
  }
  return value;
}

String _text(Object? value, String name, int maximum) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > maximum ||
      RegExp(VrWorldConstants.controlCharPattern).hasMatch(value)) {
    _fail('$name must be nonempty bounded text without control characters.');
  }
  return value;
}

double _number(Object? value, String name, double minimum, double maximum) {
  if (value is! num || !value.isFinite || value < minimum || value > maximum) {
    _fail('$name must be a finite number in [$minimum,$maximum].');
  }
  return value.toDouble();
}

int _integer(Object? value, String name, int minimum, int maximum) {
  if (value is! int || value < minimum || value > maximum) {
    _fail('$name must be an integer in [$minimum,$maximum].');
  }
  return value;
}

Never _fail(String message) => throw FormatException(message);
