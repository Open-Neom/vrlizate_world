import 'dart:typed_data';

import '../../utils/constants/vr_world_constants.dart';
import '../models/vr_world_address.dart';
import '../models/vrlw_bundle_index.dart';
import '../models/vrlw_byte_source.dart';
import 'vrlw_bundle_codec.dart';

/// Opens only the front index. Payloads remain in the source until requested.
/// A manifest digest from a trusted catalog can pin the complete chunk index;
/// the internal hashes alone do not authenticate a publisher.
final class VrlwPlaceReader {
  VrlwPlaceReader._(
    this.source,
    this.index,
    this.world,
    this.registeredPrototypeIds,
  );
  final VrlwByteSource source;
  final VrlwBundleIndex index;
  final VrWorldAddress world;
  final Set<String> registeredPrototypeIds;
  bool _closed = false;
  Future<void>? _closing;

  bool get isClosed => _closed;

  void checkOpen() {
    if (_closed) throw StateError(VrWorldConstants.errVrlwPlaceReaderClosed);
  }

  static Future<VrlwPlaceReader> open(
    VrlwByteSource source, {
    required Set<String> registeredPrototypeIds,
    String instanceId = VrWorldConstants.defaultInstanceId,
    String? expectedIndexSha256,
  }) async {
    final header = VrlwBundleCodec.parseHeader(
      await source.readRange(0, VrlwBundleCodec.headerSize),
    );
    if (source.length != header.totalLength) {
      throw const FormatException('VRLW declared and source lengths disagree.');
    }
    final index = VrlwBundleCodec.parseIndex(
      header,
      await source.readRange(VrlwBundleCodec.headerSize, header.manifestLength),
    );
    if (expectedIndexSha256 != null &&
        index.indexSha256 != expectedIndexSha256) {
      throw const FormatException(
        'VRLW index does not match the trusted catalog.',
      );
    }
    if (!registeredPrototypeIds.containsAll(index.prototypeIds)) {
      throw const FormatException('The host lacks a required VRLW prototype.');
    }
    return VrlwPlaceReader._(
      source,
      index,
      VrWorldAddress(worldId: index.id, instanceId: instanceId),
      Set.unmodifiable(registeredPrototypeIds),
    );
  }

  /// Reads only the named resource block. Results are not retained by the reader;
  /// the consuming host owns caching, complete model validation and GPU budgets.
  Future<Uint8List> readResource(String id) async {
    checkOpen();
    final resource = index.resourceAt(id);
    if (resource == null) throw FormatException('Unknown VRLW resource $id.');
    final packed = Uint8List(resource.packedBytes);
    var cursor = 0;
    while (cursor < packed.length) {
      final remaining = packed.length - cursor;
      final count = remaining > VrlwByteSource.maxReadLength
          ? VrlwByteSource.maxReadLength
          : remaining;
      final part = await source.readRange(
        index.header.payloadOffset + resource.offset + cursor,
        count,
      );
      checkOpen();
      if (part.length != count) {
        throw const FormatException(
          'Resource range length does not match index.',
        );
      }
      packed.setRange(cursor, cursor + count, part);
      cursor += count;
    }
    final bytes = VrlwBundleCodec.decodeResource(index, resource, packed);
    checkOpen();
    return bytes;
  }

  /// This closes the supplied source. Share a reader, not independently owned
  /// file handles with different expectations about lifecycle.
  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    return _closing = source.close();
  }
}
