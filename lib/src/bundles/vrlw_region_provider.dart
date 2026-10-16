import 'dart:typed_data';

import '../streaming/region_cache.dart';
import '../world_address.dart';
import '../world_entity.dart';
import 'vrlw_bundle.dart';
import 'vrlw_byte_source.dart';
import 'vrlw_chunk_decoder.dart';

/// Opens only the front index. Payloads remain in the source until requested.
/// A manifest digest from a trusted catalog can pin the complete chunk index;
/// the internal hashes alone do not authenticate a publisher.
final class VrlwPlaceReader {
  VrlwPlaceReader._(
    this.source,
    this.index,
    this.world,
    this.registeredPrototypeIds,
  );
  final VrlwByteSource source;
  final VrlwBundleIndex index;
  final VrWorldAddress world;
  final Set<String> registeredPrototypeIds;
  bool _closed = false;
  Future<void>? _closing;

  bool get isClosed => _closed;

  void _checkOpen() {
    if (_closed) throw StateError('VRLW place reader is closed.');
  }

  static Future<VrlwPlaceReader> open(
    VrlwByteSource source, {
    required Set<String> registeredPrototypeIds,
    String instanceId = 'local',
    String? expectedIndexSha256,
  }) async {
    final header = VrlwBundleCodec.parseHeader(
      await source.readRange(0, VrlwBundleCodec.headerSize),
    );
    if (source.length != header.totalLength) {
      throw const FormatException('VRLW declared and source lengths disagree.');
    }
    final index = VrlwBundleCodec.parseIndex(
      header,
      await source.readRange(VrlwBundleCodec.headerSize, header.manifestLength),
    );
    if (expectedIndexSha256 != null &&
        index.indexSha256 != expectedIndexSha256) {
      throw const FormatException(
        'VRLW index does not match the trusted catalog.',
      );
    }
    if (!registeredPrototypeIds.containsAll(index.prototypeIds)) {
      throw const FormatException('The host lacks a required VRLW prototype.');
    }
    return VrlwPlaceReader._(
      source,
      index,
      VrWorldAddress(worldId: index.id, instanceId: instanceId),
      Set.unmodifiable(registeredPrototypeIds),
    );
  }

  /// Reads only the named resource block. Results are not retained by the reader;
  /// the consuming host owns caching, complete model validation and GPU budgets.
  Future<Uint8List> readResource(String id) async {
    _checkOpen();
    final resource = index.resourceAt(id);
    if (resource == null) throw FormatException('Unknown VRLW resource $id.');
    final packed = Uint8List(resource.packedBytes);
    var cursor = 0;
    while (cursor < packed.length) {
      final remaining = packed.length - cursor;
      final count = remaining > VrlwByteSource.maxReadLength
          ? VrlwByteSource.maxReadLength
          : remaining;
      final part = await source.readRange(
        index.header.payloadOffset + resource.offset + cursor,
        count,
      );
      _checkOpen();
      if (part.length != count) {
        throw const FormatException(
          'Resource range length does not match index.',
        );
      }
      packed.setRange(cursor, cursor + count, part);
      cursor += count;
    }
    final bytes = VrlwBundleCodec.decodeResource(index, resource, packed);
    _checkOpen();
    return bytes;
  }

  /// This closes the supplied source. Share a reader, not independently owned
  /// file handles with different expectations about lifecycle.
  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    return _closing = source.close();
  }
}

/// Plugs a place directly into [VrRegionCache], with optional persistent bytes.
/// Only packed region bytes are cached; entities are always validated on reuse.
final class VrlwRegionProvider {
  VrlwRegionProvider(
    this.reader, {
    this.readCache,
    this.writeCache,
    VrlwChunkDecoder? chunkDecoder,
  }) : _chunkDecoder = chunkDecoder ?? const DefaultVrlwChunkDecoder(),
       grid = VrRegionGrid(
         world: reader.world,
         gridId: 'vrlw:${reader.index.indexSha256}',
         cellSizeMeters: reader.index.cellSizeMeters,
       );

  final VrlwPlaceReader reader;
  final VrRegionGrid grid;
  final Future<Uint8List?> Function(String)? readCache;
  final Future<bool> Function(String, Uint8List)? writeCache;
  final VrlwChunkDecoder _chunkDecoder;
  int cacheHits = 0, sourceReads = 0, sourceBytes = 0;

  Future<VrRegionData<List<VrWorldEntity>>> load(
    VrRegionKey key,
    VrRegionCancellation cancellation,
  ) async {
    cancellation.throwIfCancelled();
    reader._checkOpen();
    if (key.world != grid.world || key.gridId != grid.gridId) {
      throw const FormatException(
        'Region belongs to a different place or revision.',
      );
    }
    final chunk = reader.index.chunkAt(key.x, key.z);
    if (chunk == null) {
      return VrRegionData(value: const [], sizeBytes: 64);
    }
    Future<List<VrWorldEntity>> decode(Uint8List packed) async =>
        _chunkDecoder.decode(
          index: reader.index,
          chunk: chunk,
          packedBytes: packed,
          world: reader.world,
          registeredPrototypeIds: reader.registeredPrototypeIds,
        );
    VrRegionData<List<VrWorldEntity>> resident(List<VrWorldEntity> entities) =>
        VrRegionData(
          value: List.unmodifiable(entities),
          sizeBytes: chunk.unpackedBytes * 4 + entities.length * 384 + 256,
        );
    Uint8List? packed;
    try {
      packed = await readCache?.call(key.cacheKey);
    } catch (_) {
      // Unavailable disposable storage does not prevent source access.
    }
    cancellation.throwIfCancelled();
    reader._checkOpen();
    if (packed != null) {
      try {
        final entities = await decode(packed);
        cancellation.throwIfCancelled();
        reader._checkOpen();
        cacheHits++;
        return resident(entities);
      } on FormatException {
        // A corrupt cached block is replaced from the pinned source below.
      }
    }
    cancellation.throwIfCancelled();
    reader._checkOpen();
    packed = await reader.source.readRange(
      reader.index.header.payloadOffset + chunk.offset,
      chunk.packedBytes,
    );
    cancellation.throwIfCancelled();
    reader._checkOpen();
    sourceReads++;
    sourceBytes += packed.length;
    if (packed.length != chunk.packedBytes) {
      throw const FormatException('Packed region length does not match index.');
    }
    // Keep the validated bytes for the eventual cache write independent of a
    // custom source that reuses/mutates its read buffer while decoding awaits.
    packed = Uint8List.fromList(packed);
    final entities = await decode(packed);
    cancellation.throwIfCancelled();
    reader._checkOpen();
    try {
      await writeCache?.call(key.cacheKey, packed);
    } catch (_) {
      // Never confuse a region cache with durable user state.
    }
    cancellation.throwIfCancelled();
    reader._checkOpen();
    return resident(entities);
  }
}
