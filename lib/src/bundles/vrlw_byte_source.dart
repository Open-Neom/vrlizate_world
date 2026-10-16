import 'dart:typed_data';

/// Bounded random access to a single immutable .vrlw representation.
///
/// Sources return exactly the requested bytes or fail. A successful first read
/// establishes [length]; a source must not silently switch versions afterward.
abstract interface class VrlwByteSource {
  static const maxLength = 128 * 1024 * 1024;
  static const maxReadLength = 1024 * 1024;

  int? get length;
  Future<Uint8List> readRange(int offset, int length);
  Future<void> close();
}

/// An isolated in-memory representation. Both input and returned ranges copy.
final class VrlwMemorySource implements VrlwByteSource {
  VrlwMemorySource(Uint8List bytes) : _bytes = _copy(bytes);

  final Uint8List _bytes;
  bool _closed = false;

  @override
  int get length => _bytes.length;

  @override
  Future<Uint8List> readRange(int offset, int length) async {
    if (_closed) throw StateError('VRLW source is closed.');
    validateVrlwRange(offset, length, totalLength: _bytes.length);
    return Uint8List.fromList(_bytes.sublist(offset, offset + length));
  }

  @override
  Future<void> close() async => _closed = true;

  static Uint8List _copy(Uint8List bytes) {
    if (bytes.length > VrlwByteSource.maxLength) {
      throw const FormatException('VRLW source exceeds its byte budget.');
    }
    return Uint8List.fromList(bytes);
  }
}

/// Shared source bounds. Zero-length reads are intentionally unsupported.
void validateVrlwRange(int offset, int length, {int? totalLength}) {
  final maximum = totalLength ?? VrlwByteSource.maxLength;
  if (offset < 0 ||
      length <= 0 ||
      length > VrlwByteSource.maxReadLength ||
      offset > maximum - length) {
    throw RangeError('VRLW range exceeds its source or read budget.');
  }
}
