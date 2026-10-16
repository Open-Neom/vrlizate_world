import 'dart:async';
import 'dart:typed_data';

import '../world_address.dart';
import '../world_entity.dart';
import 'vrlw_bundle.dart';
import 'vrlw_chunk_decode_request.dart';
import 'vrlw_chunk_worker_inline.dart'
    if (dart.library.io) 'vrlw_chunk_worker_native.dart'
    as worker;

/// Trusted host scheduling boundary, also injectable in lifecycle tests.
/// Implementations must preserve all validation performed by the bundle codec,
/// own mutable input before awaiting, and never accept downloaded Dart code.
abstract interface class VrlwChunkDecoder {
  FutureOr<List<VrWorldEntity>> decode({
    required VrlwBundleIndex index,
    required VrlwChunkIndex chunk,
    required Uint8List packedBytes,
    required VrWorldAddress world,
    required Set<String> registeredPrototypeIds,
  });
}

/// Tiny regions decode inline. Larger native regions use a fresh isolate;
/// web remains inline. The threshold is a heuristic, not a frame-time promise.
///
/// Worker input/output remain bounded by the codec's byte/entity limits. The
/// caller's region cache bounds concurrent loads (and therefore worker count).
/// An isolate has startup overhead; this is not a persistent worker pool.
final class DefaultVrlwChunkDecoder implements VrlwChunkDecoder {
  const DefaultVrlwChunkDecoder();

  static const backgroundThresholdBytes = 64 * 1024;

  @override
  FutureOr<List<VrWorldEntity>> decode({
    required VrlwBundleIndex index,
    required VrlwChunkIndex chunk,
    required Uint8List packedBytes,
    required VrWorldAddress world,
    required Set<String> registeredPrototypeIds,
  }) {
    // Reject oversize/mismatched cache input before copying it for a worker.
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
