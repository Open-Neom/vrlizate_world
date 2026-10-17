import 'dart:async';
import 'dart:typed_data';

import '../../src/bundles/vrlw_chunk_worker_inline.dart'
    if (dart.library.io) '../../src/bundles/vrlw_chunk_worker_native.dart'
    as worker;
import '../../utils/constants/vr_world_constants.dart';
import '../models/vr_world_address.dart';
import '../models/vr_world_entity.dart';
import '../models/vrlw_bundle_index.dart';
import '../models/vrlw_chunk_decode_request.dart';
import '../models/vrlw_chunk_index.dart';
import 'vrlw_bundle_codec.dart';
import 'vrlw_chunk_decoder.dart';

/// Tiny regions decode inline. Larger native regions use a fresh isolate;
/// web remains inline. The threshold is a heuristic, not a frame-time promise.
final class DefaultVrlwChunkDecoder implements VrlwChunkDecoder {
  const DefaultVrlwChunkDecoder();

  static const backgroundThresholdBytes =
      VrWorldConstants.backgroundDecodeThresholdBytes;

  @override
  FutureOr<List<VrWorldEntity>> decode({
    required VrlwBundleIndex index,
    required VrlwChunkIndex chunk,
    required Uint8List packedBytes,
    required VrWorldAddress world,
    required Set<String> registeredPrototypeIds,
  }) {
    if (packedBytes.length != chunk.packedBytes) {
      throw const FormatException('Packed region length does not match index.');
    }
    if (chunk.unpackedBytes < backgroundThresholdBytes) {
      return VrlwBundleCodec.decodeChunk(
        index,
        chunk,
        packedBytes,
        world: world,
        registeredPrototypeIds: registeredPrototypeIds,
      );
    }
    return worker.decodeVrlwChunkInBackground(
      VrlwChunkDecodeRequest(
        index: index,
        chunk: chunk,
        packedBytes: packedBytes,
        world: world,
        registeredPrototypeIds: registeredPrototypeIds,
      ),
    );
  }
}
