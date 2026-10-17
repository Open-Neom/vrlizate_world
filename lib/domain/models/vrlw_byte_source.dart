import 'dart:typed_data';

import '../../utils/constants/vr_world_constants.dart';

/// Bounded random access to a single immutable .vrlw representation.
///
/// Sources return exactly the requested bytes or fail. A successful first read
/// establishes [length]; a source must not silently switch versions afterward.
abstract interface class VrlwByteSource {
  static const maxLength = VrWorldConstants.vrlwMaxFileBytes;
  static const maxReadLength = VrWorldConstants.vrlwMaxReadLength;

  int? get length;
  Future<Uint8List> readRange(int offset, int length);
  Future<void> close();
}
