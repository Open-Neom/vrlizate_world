import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A fixed capacity output; every write checks the limit BEFORE copying. The
/// inflater sees at most the admitted chunk allocation plus its fixed tables.
final class VrlwBoundedOutput extends OutputStream {
  VrlwBoundedOutput(int maximum)
    : _buffer = Uint8List(maximum),
      super(byteOrder: ByteOrder.littleEndian);

  final Uint8List _buffer;
  int _length = 0;

  @override
  int get length => _length;

  void _reserve(int count) {
    if (count < 0 || _length + count > _buffer.length) {
      throw const FormatException(
        'DEFLATE output exceeds its declared byte budget.',
      );
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
      throw const FormatException('Invalid DEFLATE back-reference.');
    }
    return Uint8List.sublistView(_buffer, first, last);
  }

  @override
  void clear() => _length = 0;

  @override
  void flush() {}
}
