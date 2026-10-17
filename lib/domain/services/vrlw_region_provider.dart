import 'dart:typed_data';

import '../../utils/constants/vr_world_constants.dart';
import '../models/vr_region_cancellation.dart';
import '../models/vr_region_data.dart';
import '../models/vr_region_grid.dart';
import '../models/vr_region_key.dart';
import '../models/vr_world_entity.dart';
import 'default_vrlw_chunk_decoder.dart';
import 'vrlw_chunk_decoder.dart';
import 'vrlw_place_reader.dart';

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
    reader.checkOpen();
    if (key.world != grid.world || key.gridId != grid.gridId) {
      throw const FormatException(
        'Region belongs to a different place or revision.',
      );
    }
    final chunk = reader.index.chunkAt(key.x, key.z);
    if (chunk == null) {
      return VrRegionData(
        value: const [],
        sizeBytes: VrWorldConstants.emptyRegionResidentBytes,
      );
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
          sizeBytes:
              chunk.unpackedBytes *
                  VrWorldConstants.residentUnpackedMultiplier +
              entities.length * VrWorldConstants.residentEntityOverheadBytes +
              VrWorldConstants.residentBaseOverheadBytes,
        );
    Uint8List? packed;
    try {
      packed = await readCache?.call(key.cacheKey);
    } catch (_) {
      // Unavailable disposable storage does not prevent source access.
    }
    cancellation.throwIfCancelled();
    reader.checkOpen();
    if (packed != null) {
      try {
        final entities = await decode(packed);
        cancellation.throwIfCancelled();
        reader.checkOpen();
        cacheHits++;
        return resident(entities);
      } on FormatException {
        // A corrupt cached block is replaced from the pinned source below.
      }
    }
    cancellation.throwIfCancelled();
    reader.checkOpen();
    packed = await reader.source.readRange(
      reader.index.header.payloadOffset + chunk.offset,
      chunk.packedBytes,
    );
    cancellation.throwIfCancelled();
    reader.checkOpen();
    sourceReads++;
    sourceBytes += packed.length;
    if (packed.length != chunk.packedBytes) {
      throw const FormatException('Packed region length does not match index.');
    }
    packed = Uint8List.fromList(packed);
    final entities = await decode(packed);
    cancellation.throwIfCancelled();
    reader.checkOpen();
    try {
      await writeCache?.call(key.cacheKey, packed);
    } catch (_) {
      // Never confuse a region cache with durable user state.
    }
    cancellation.throwIfCancelled();
    reader.checkOpen();
    return resident(entities);
  }
}
