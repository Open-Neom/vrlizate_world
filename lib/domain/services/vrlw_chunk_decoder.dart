import 'dart:async';
import 'dart:typed_data';

import '../models/vr_world_address.dart';
import '../models/vr_world_entity.dart';
import '../models/vrlw_bundle_index.dart';
import '../models/vrlw_chunk_index.dart';

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
