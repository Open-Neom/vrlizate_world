import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;

import '../world_address.dart';
import '../world_entity.dart';

/// The fixed prefix of an experimental, indexed `.vrlw` world data bundle.
///
/// All offsets are bytes. The payload contains independent region chunks,
/// allowing transports to fetch the index and then only nearby regions.
final class VrlwBundleHeader {
  const VrlwBundleHeader._(this.manifestLength, this.packedPayloadLength);

  final int manifestLength;
  final int packedPayloadLength;
  int get payloadOffset => VrlwBundleCodec.headerSize + manifestLength;
  int get totalLength => payloadOffset + packedPayloadLength;
}

/// A region's independently compressed and hashed payload.
/// [offset] is relative to [VrlwBundleHeader.payloadOffset].
final class VrlwChunkIndex {
  const VrlwChunkIndex._({
    required this.x,
    required this.z,
    required this.offset,
    required this.packedBytes,
    required this.unpackedBytes,
    required this.codec,
    required this.sha256,
  });

  final int x;
  final int z;
  final int offset;
  final int packedBytes;
  final int unpackedBytes;
  final String codec;
  final String sha256;

  Map<String, Object> _toJson() => {
    'x': x,
    'z': z,
    'offset': offset,
    'packedBytes': packedBytes,
    'unpackedBytes': unpackedBytes,
    'codec': codec,
    'sha256': sha256,
  };
}

/// An independently readable, bounded resource owned by one parsed index.
/// [offset] is relative to the payload, following every region block.
final class VrlwResourceIndex {
  const VrlwResourceIndex._({
    required this.id,
    required this.type,
    required this.offset,
    required this.packedBytes,
    required this.unpackedBytes,
    required this.codec,
    required this.sha256,
    this.width,
    this.height,
  });
  final String id, type, codec, sha256;
  final int offset, packedBytes, unpackedBytes;
  final int? width, height;

  Map<String, Object> _toJson() => {
    'id': id,
    'type': type,
    'offset': offset,
    'packedBytes': packedBytes,
    'unpackedBytes': unpackedBytes,
    'codec': codec,
    'sha256': sha256,
    if (width != null) 'width': width!,
    if (height != null) 'height': height!,
  };
}

/// Bounding collision primitive declared for a prototype in a `.vrlw` bundle.
final class VrlwColliderSpec {
  const VrlwColliderSpec._({
    required this.shape,
    this.halfExtents,
    this.radius,
    this.height,
    this.offset = const [0, 0, 0],
  });

  /// One of `'box'`, `'sphere'`, `'cylinder'`, or `'capsule'`.
  final String shape;

  /// Half-extents `[hx, hy, hz]` in meters when [shape] is `'box'`.
  final List<double>? halfExtents;

  /// Radius in meters when [shape] is `'sphere'`, `'cylinder'`, or `'capsule'`.
  final double? radius;

  /// Total height in meters when [shape] is `'cylinder'` or `'capsule'`.
  final double? height;

  /// Local center offset `[x, y, z]` in meters relative to prototype origin.
  final List<double> offset;

  Map<String, Object> _toJson() => {
    'shape': shape,
    if (halfExtents != null) 'halfExtents': halfExtents!,
    if (radius != null) 'radius': radius!,
    if (height != null) 'height': height!,
    if (offset[0] != 0 || offset[1] != 0 || offset[2] != 0) 'offset': offset,
  };
}

/// Declares static data for a prototype, not permission to instantiate it.
/// The host validates the model profile before registering the prototype.
final class VrlwPrototypeBinding {
  const VrlwPrototypeBinding._({
    required this.prototypeId,
    required this.model,
    this.baseColorTexture,
    this.normalTexture,
    this.metallicRoughnessTexture,
    this.emissiveTexture,
    this.occlusionTexture,
    this.audio,
    this.collider,
    this.castsShadows,
  });
  final String prototypeId, model;
  final String? baseColorTexture;
  final String? normalTexture;
  final String? metallicRoughnessTexture;
  final String? emissiveTexture;
  final String? occlusionTexture;
  final String? audio;
  final VrlwColliderSpec? collider;
  final bool? castsShadows;

  Map<String, Object> _toJson() => {
    'prototypeId': prototypeId,
    'model': model,
    if (baseColorTexture != null) 'baseColorTexture': baseColorTexture!,
    if (normalTexture != null) 'normalTexture': normalTexture!,
    if (metallicRoughnessTexture != null)
      'metallicRoughnessTexture': metallicRoughnessTexture!,
    if (emissiveTexture != null) 'emissiveTexture': emissiveTexture!,
    if (occlusionTexture != null) 'occlusionTexture': occlusionTexture!,
    if (audio != null) 'audio': audio!,
    if (collider != null) 'collider': collider!._toJson(),
    if (castsShadows != null) 'castsShadows': castsShadows!,
  };
}

/// World-level lighting, IBL/skybox, exposure, and directional sun parameters.
final class VrlwEnvironmentSpec {
  const VrlwEnvironmentSpec._({
    this.environmentResource,
    this.skyboxResource,
    this.environmentIntensity,
    this.exposure,
    this.sunDirection,
    this.sunColor,
    this.sunIntensity,
    this.castsShadows,
  });

  final String? environmentResource;
  final String? skyboxResource;
  final double? environmentIntensity;
  final double? exposure;
  final List<double>? sunDirection;
  final List<double>? sunColor;
  final double? sunIntensity;
  final bool? castsShadows;

  Map<String, Object> _toJson() => {
    if (environmentResource != null)
      'environmentResource': environmentResource!,
    if (skyboxResource != null) 'skyboxResource': skyboxResource!,
    if (environmentIntensity != null)
      'environmentIntensity': environmentIntensity!,
    if (exposure != null) 'exposure': exposure!,
    if (sunDirection != null) 'sunDirection': sunDirection!,
    if (sunColor != null) 'sunColor': sunColor!,
    if (sunIntensity != null) 'sunIntensity': sunIntensity!,
    if (castsShadows != null) 'castsShadows': castsShadows!,
  };
}

/// Positional spatial audio emitter bound to a packaged `audio.*` resource.
final class VrlwAudioEmitter {
  const VrlwAudioEmitter._({
    required this.id,
    required this.resource,
    required this.x,
    required this.y,
    required this.z,
    this.volume = 1.0,
    this.maxDistance = 24.0,
    this.loop = true,
  });

  final String id;
  final String resource;
  final double x, y, z;
  final double volume;
  final double maxDistance;
  final bool loop;

  Map<String, Object> _toJson() => {
    'id': id,
    'resource': resource,
    'x': x,
    'y': y,
    'z': z,
    'volume': volume,
    'maxDistance': maxDistance,
    'loop': loop,
  };
}

/// Content-addressed reference to an external/linked `.vrlw` world bundle.
final class VrlwWorldDependency {
  const VrlwWorldDependency._({
    required this.alias,
    required this.id,
    required this.revision,
    required this.indexSha256,
    this.url,
  });

  final String alias;
  final String id;
  final String revision;
  final String indexSha256;
  final String? url;

  Map<String, Object> _toJson() => {
    'alias': alias,
    'id': id,
    'revision': revision,
    'indexSha256': indexSha256,
    if (url != null) 'url': url!,
  };
}

/// Validated metadata. It does not retain compressed payload or decoded objects.
///
/// [indexSha256] identifies the exact index bytes and includes chunk digests;
/// hosts can use it to avoid stale cache entries when a publisher changes data.
/// Digests detect corruption, but are NOT publisher authentication or signatures.
final class VrlwBundleIndex {
  VrlwBundleIndex._({
    required this.header,
    required _Metadata metadata,
    required this.indexSha256,
    required List<VrlwChunkIndex> chunks,
    required List<VrlwResourceIndex> resources,
    required List<VrlwPrototypeBinding> prototypeBindings,
    this.environment,
    List<VrlwAudioEmitter> audioEmitters = const [],
    List<VrlwWorldDependency> dependencies = const [],
  }) : id = metadata.id,
       title = metadata.title,
       revision = metadata.revision,
       license = metadata.license,
       gridId = metadata.gridId,
       cellSizeMeters = metadata.cellSizeMeters,
       prototypeIds = metadata.prototypeIds,
       origin = metadata.origin,
       chunks = List.unmodifiable(chunks),
       resources = List.unmodifiable(resources),
       prototypeBindings = List.unmodifiable(prototypeBindings),
       audioEmitters = List.unmodifiable(audioEmitters),
       dependencies = List.unmodifiable(dependencies),
       _resourcesById = {
         for (final resource in resources) resource.id: resource,
       },
       _byCell = {for (final chunk in chunks) (chunk.x, chunk.z): chunk};

  final VrlwBundleHeader header;
  final String id;
  final String title;
  final String revision;
  final String license;
  final String gridId;
  final double cellSizeMeters;
  final Set<String> prototypeIds;

  /// Schema v1 uses meters and Y-up. `local`: +X right, -Z forward.
  /// `wgs84-enu`: +X east, -Z north, Y ellipsoid-normal up; ellipsoidal height
  /// is NOT sea-level altitude. Earth hosts explicitly adopt this origin.
  final Map<String, Object?> origin;
  final String indexSha256;
  final List<VrlwChunkIndex> chunks;
  final List<VrlwResourceIndex> resources;
  final List<VrlwPrototypeBinding> prototypeBindings;
  final VrlwEnvironmentSpec? environment;
  final List<VrlwAudioEmitter> audioEmitters;
  final List<VrlwWorldDependency> dependencies;
  final Map<String, VrlwResourceIndex> _resourcesById;
  final Map<(int, int), VrlwChunkIndex> _byCell;

  VrlwChunkIndex? chunkAt(int x, int z) => _byCell[(x, z)];
  VrlwResourceIndex? resourceAt(String id) => _resourcesById[id];
}

/// Experimental data-only regional world format; this never executes Dart,
/// loads plugins, or instantiates unregistered prototypes.
///
/// Header: ASCII `VRLW0001`, uint32LE index length, uint32LE payload length.
/// The UTF-8 JSON index precedes contiguous independently compressed chunks.
/// Each chunk is UTF-8 JSON `{ "entities": [...] }`. Entity X/Z coordinates
/// are region-local; the decoder adds the region's origin in meters.
///
/// The compiler accepts the index metadata plus `regions` (instead of `chunks`)
/// containing `{x,z,entities:[{id,prototypeId,x,y,z,yawRadians?,scale?}]}`.
/// Compression uses standard raw DEFLATE; STORE is selected when smaller.
abstract final class VrlwBundleCodec {
  static const headerSize = 16;
  static const maxManifestBytes = 1024 * 1024;
  static const maxChunks = 1024;
  static const maxPackedChunkBytes = 512 * 1024;
  static const maxUnpackedChunkBytes = 2 * 1024 * 1024;
  static const maxFileBytes = 128 * 1024 * 1024;
  static const maxTotalUnpackedBytes = 256 * 1024 * 1024;
  static const maxEntitiesPerChunk = 4096;
  static const maxResources = 32;
  static const maxResourceBytes = 4 * 1024 * 1024;
  static const maxTotalResourceBytes = 16 * 1024 * 1024;
  static const maxTextureDimension = 512;
  static const maxCompressedTextureDimension = 2048;
  static const maxAudioEmitters = 64;
  static const maxDependencies = 32;
  static const _magic = 'VRLW0001';

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
    final header = VrlwBundleHeader._(manifestLength, payloadLength);
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
    final metadata = _Metadata.parse(document);
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
      if (digest is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
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
        VrlwChunkIndex._(
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
      if (digest is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
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
        VrlwResourceIndex._(
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
    final dependencies = _dependencies(document, metadata.id);
    if (nextOffset != header.packedPayloadLength) {
      _fail('Unindexed or missing payload bytes.');
    }
    return VrlwBundleIndex._(
      header: header,
      metadata: metadata,
      indexSha256: crypto.sha256.convert(manifestBytes).toString(),
      chunks: chunks,
      resources: resources,
      prototypeBindings: bindings,
      environment: environment,
      audioEmitters: audioEmitters,
      dependencies: dependencies,
    );
  }

  /// Decodes one resource with integrity, bounded expansion and envelope checks.
  /// `model.glb` still needs the host's complete static-geometry validator before
  /// passing it to a GPU importer; this layer checks only the GLB container.
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
  /// Only named, declared AND host-registered prototypes may be instantiated.
  /// A registry must still reject ID conflicts between independently loaded
  /// untrusted chunks. The compiler checks all regions for such duplicates.
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
      // Do not use platform ZLibDecoder here: its native implementation can
      // allocate all expanded bytes before an OutputStream receives them.
      final output = _BoundedOutput(chunk.unpackedBytes);
      // A few sentinel bytes let Inflate finish a short end-of-block Huffman
      // code despite its table lookahead. On successful termination it rewinds
      // all whole lookahead bytes, so the cursor must stop at the real boundary.
      // Missing final blocks instead consume the sentinel and are rejected.
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
  /// This is packaging, validation and compression, NOT Dart AOT compilation.
  static Uint8List encode(Map<String, Object?> source, {bool compress = true}) {
    _keys(source, {..._metadataKeys, 'regions', ..._resourceKeys}, 'source');
    final metadata = _Metadata.parse(source);
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
              .map((placement) => placement.toJson())
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
        VrlwChunkIndex._(
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
        VrlwResourceIndex._(
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
    final dependencies = _dependencies(source, metadata.id);
    final manifest = utf8.encode(
      jsonEncode({
        ...metadata.toJson(),
        'chunks': chunks.map((chunk) => chunk._toJson()).toList(),
        if (source.containsKey('resources'))
          'resources': resources.map((resource) => resource._toJson()).toList(),
        if (source.containsKey('prototypeBindings'))
          'prototypeBindings': bindings
              .map((binding) => binding._toJson())
              .toList(),
        if (environment != null) 'environment': environment._toJson(),
        if (source.containsKey('audioEmitters'))
          'audioEmitters': audioEmitters.map((e) => e._toJson()).toList(),
        if (source.containsKey('dependencies'))
          'dependencies': dependencies.map((d) => d._toJson()).toList(),
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
      VrlwPrototypeBinding._(
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
    return VrlwColliderSpec._(
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
    return VrlwColliderSpec._(
      shape: shape,
      radius: radius,
      offset: List.unmodifiable(offset),
    );
  }
  final height = _number(map['height'], 'collider height', 0.001, 1000);
  return VrlwColliderSpec._(
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
  return VrlwEnvironmentSpec._(
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
      VrlwAudioEmitter._(
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
    _keys(map, {
      'alias',
      'id',
      'revision',
      'indexSha256',
      'url',
    }, 'dependency');
    final alias = _identifier(map['alias'], 'dependency alias');
    if (!aliases.add(alias)) _fail('Duplicate dependency alias $alias.');
    final id = _identifier(map['id'], 'dependency id');
    if (id == selfWorldId || !ids.add(id)) {
      _fail('Self or duplicate dependency world id $id.');
    }
    final revision = _identifier(map['revision'], 'dependency revision');
    final digest = map['indexSha256'];
    if (digest is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
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
      VrlwWorldDependency._(
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
  final output = _BoundedOutput(resource.unpackedBytes);
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
    if (bytes.length < 33) _fail('Truncated PNG resource.');
    for (var i = 0; i < _pngSignature.length; i++) {
      if (bytes[i] != _pngSignature[i]) _fail('Invalid PNG signature.');
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(8) != 13 || data.getUint32(12) != 0x49484452) {
      _fail('PNG resource requires an initial IHDR chunk.');
    }
    final pngW = data.getUint32(16);
    final pngH = data.getUint32(20);
    if (pngW < 1 ||
        pngW > VrlwBundleCodec.maxCompressedTextureDimension ||
        pngH < 1 ||
        pngH > VrlwBundleCodec.maxCompressedTextureDimension) {
      _fail('PNG dimensions exceed portable texture budget.');
    }
    if ((width != null && pngW != width) ||
        (height != null && pngH != height)) {
      _fail('PNG IHDR dimensions do not match declared width/height.');
    }
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
  // Deliberately only an envelope validator. Apps validates JSON, attributes,
  // URLs, geometry and supported extensions before an importer sees this GLB.
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

final class _Metadata {
  _Metadata({
    required this.id,
    required this.title,
    required this.revision,
    required this.license,
    required this.gridId,
    required this.cellSizeMeters,
    required this.prototypeIds,
    required this.origin,
  });

  factory _Metadata.parse(Map<String, Object?> map) {
    if (map['schemaVersion'] is! int || map['schemaVersion'] != 1) {
      _fail('Unsupported world schema version.');
    }
    final prototypes = <String>{};
    for (final raw in _list(map['prototypes'], 'prototypes', 1024)) {
      final id = _identifier(raw, 'prototype');
      if (!prototypes.add(id)) _fail('Duplicate prototype declaration.');
    }
    return _Metadata(
      id: _identifier(map['id'], 'id'),
      title: _text(map['title'], 'title', 160),
      revision: _identifier(map['revision'], 'revision'),
      license: _text(map['license'], 'license', 2048),
      gridId: _identifier(map['gridId'], 'gridId'),
      cellSizeMeters: _number(
        map['cellSizeMeters'],
        'cellSizeMeters',
        0.1,
        VrWorldPosition.maximumCoordinateMeters,
      ),
      prototypeIds: Set.unmodifiable(prototypes),
      origin: _origin(map['origin']),
    );
  }

  final String id;
  final String title;
  final String revision;
  final String license;
  final String gridId;
  final double cellSizeMeters;
  final Set<String> prototypeIds;
  final Map<String, Object?> origin;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'title': title,
    'revision': revision,
    'license': license,
    'gridId': gridId,
    'cellSizeMeters': cellSizeMeters,
    'prototypes': prototypeIds.toList(),
    'origin': origin,
  };
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

final class _Placement {
  _Placement(
    this.id,
    this.prototypeId,
    this.x,
    this.y,
    this.z,
    this.yawRadians,
    this.scale,
  );

  final String id;
  final String prototypeId;
  final double x;
  final double y;
  final double z;
  final double yawRadians;
  final double scale;

  Map<String, Object> toJson() => {
    'id': id,
    'prototypeId': prototypeId,
    'x': x,
    'y': y,
    'z': z,
    'yawRadians': yawRadians,
    'scale': scale,
  };
}

List<_Placement> _placements(
  Object? value, {
  required double cellSizeMeters,
  required Set<String> prototypeIds,
}) {
  final result = <_Placement>[];
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
    result.add(_Placement(id, prototype, x, y, z, yaw, scale));
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
  // Reject excessive nesting before jsonDecode allocates nested containers or
  // recurses. Sizes are already bounded by the header/chunk admission checks.
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
    validateWorldIdentifier(value, name);
  } on ArgumentError {
    _fail('Invalid $name identifier.');
  }
  return value;
}

String _text(Object? value, String name, int maximum) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > maximum ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
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

/// A fixed capacity output; every write checks the limit BEFORE copying. The
/// inflater sees at most the admitted chunk allocation plus its fixed tables.
final class _BoundedOutput extends OutputStream {
  _BoundedOutput(int maximum)
    : _buffer = Uint8List(maximum),
      super(byteOrder: ByteOrder.littleEndian);

  final Uint8List _buffer;
  int _length = 0;
  @override
  int get length => _length;

  void _reserve(int count) {
    if (count < 0 || _length + count > _buffer.length) {
      _fail('DEFLATE output exceeds its declared byte budget.');
    }
  }

  @override
  void writeByte(int value) {
    _reserve(1);
    _buffer[_length++] = value;
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    _reserve(count);
    _buffer.setRange(_length, _length + count, bytes);
    _length += count;
  }

  @override
  void writeStream(InputStream stream) {
    final count = stream.length;
    _reserve(count);
    writeBytes(stream.toUint8List());
  }

  @override
  Uint8List subset(int start, [int? end]) {
    final first = start < 0 ? _length + start : start;
    final last = end == null ? _length : (end < 0 ? _length + end : end);
    if (first < 0 || last < first || last > _length) {
      _fail('Invalid DEFLATE back-reference.');
    }
    return Uint8List.sublistView(_buffer, first, last);
  }

  @override
  void clear() => _length = 0;
  @override
  void flush() {}
}
