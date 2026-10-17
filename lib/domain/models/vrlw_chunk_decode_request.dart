import 'dart:typed_data';

import '../services/vrlw_bundle_codec.dart';
import 'vr_world_address.dart';
import 'vr_world_entity.dart';
import 'vrlw_bundle_index.dart';
import 'vrlw_chunk_index.dart';

/// Data-only worker input. In particular, no reader, source, disk cache, or
/// platform object is retained by the bound [decode] method sent to an isolate.
final class VrlwChunkDecodeRequest {
  VrlwChunkDecodeRequest({
    required this.index,
    required this.chunk,
    required Uint8List packedBytes,
    required this.world,
    required Set<String> registeredPrototypeIds,
  }) : packedBytes = Uint8List.fromList(packedBytes),
       registeredPrototypeIds = Set.unmodifiable(registeredPrototypeIds);

  final VrlwBundleIndex index;
  final VrlwChunkIndex chunk;
  final Uint8List packedBytes;
  final VrWorldAddress world;
  final Set<String> registeredPrototypeIds;

  List<VrWorldEntity> decode() => VrlwBundleCodec.decodeChunk(
    index,
    chunk,
    packedBytes,
    world: world,
    registeredPrototypeIds: registeredPrototypeIds,
  );
}
