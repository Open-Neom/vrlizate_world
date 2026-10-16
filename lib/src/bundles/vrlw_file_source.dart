import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'vrlw_byte_source.dart';

/// Native, read-only access; no archive extraction or executable loading.
///
/// Reads serialize seek operations and reject size/mtime changes relative to
/// open. This detects ordinary mutation, not malicious metadata spoofing; the
/// bundle reader must additionally verify each region's cryptographic digest.
final class VrlwFileSource implements VrlwByteSource {
  VrlwFileSource._(this._file, this._handle, this._snapshot);

  static Future<VrlwFileSource> open(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException('VRLW source must be a regular file.', path);
    }
    final file = File(path);
    final snapshot = await file.stat();
    if (snapshot.size > VrlwByteSource.maxLength) {
      throw const FormatException('VRLW file exceeds its byte budget.');
    }
    final handle = await file.open(mode: FileMode.read);
    final source = VrlwFileSource._(file, handle, snapshot);
    try {
      await source._assertUnchanged();
      return source;
    } catch (_) {
      await handle.close();
      rethrow;
    }
  }

  final File _file;
  final RandomAccessFile _handle;
  final FileStat _snapshot;
  Future<void> _queue = Future<void>.value();
  Future<void>? _closing;
  bool _closed = false;

  @override
  int get length => _snapshot.size;

  @override
  Future<Uint8List> readRange(int offset, int length) {
    if (_closed) return Future.error(StateError('VRLW source is closed.'));
    return _serialize(() async {
      if (_closed) throw StateError('VRLW source is closed.');
      validateVrlwRange(offset, length, totalLength: this.length);
      await _assertUnchanged();
      await _handle.setPosition(offset);
      final bytes = await _handle.read(length);
      await _assertUnchanged();
      if (_closed) throw StateError('VRLW source is closed.');
      if (bytes.length != length) {
        throw const FormatException('VRLW file returned an incomplete range.');
      }
      return bytes;
    });
  }

  Future<void> _assertUnchanged() async {
    final current = await _file.stat();
    if (await FileSystemEntity.type(_file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        current.type != FileSystemEntityType.file ||
        current.size != _snapshot.size ||
        current.modified != _snapshot.modified ||
        await _handle.length() != _snapshot.size) {
      throw FileSystemException(
        'VRLW file changed while its source was open.',
        _file.path,
      );
    }
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final operation = _queue.then((_) => action());
    _queue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  @override
  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    return _closing = _serialize(() async {
      await _handle.close();
    });
  }
}
