import 'dart:typed_data';

import '../../utils/constants/vr_world_constants.dart';
import '../../utils/vr_world_validator.dart';
import '../models/vrlw_byte_source.dart';

/// An isolated in-memory representation. Both input and returned ranges copy.
final class VrlwMemorySource implements VrlwByteSource {
  VrlwMemorySource(Uint8List bytes) : _bytes = _copy(bytes);

  final Uint8List _bytes;
  bool _closed = false;

  @override
  int get length => _bytes.length;

  @override
  Future<Uint8List> readRange(int offset, int length) async {
    if (_closed) throw StateError(VrWorldConstants.errVrlwSourceClosed);
    VrWorldValidator.validateRange(offset, length, totalLength: _bytes.length);
    return Uint8List.fromList(_bytes.sublist(offset, offset + length));
  }

  @override
  Future<void> close() async => _closed = true;

  static Uint8List _copy(Uint8List bytes) {
    if (bytes.length > VrlwByteSource.maxLength) {
      throw const FormatException(VrWorldConstants.errVrlwSourceBudget);
    }
    return Uint8List.fromList(bytes);
  }
}
