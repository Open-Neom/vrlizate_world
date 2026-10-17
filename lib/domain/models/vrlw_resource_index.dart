/// An independently readable, bounded resource owned by one parsed index.
/// [offset] is relative to the payload, following every region block.
final class VrlwResourceIndex {
  const VrlwResourceIndex({
    required this.id,
    required this.type,
    required this.offset,
    required this.packedBytes,
    required this.unpackedBytes,
    required this.codec,
    required this.sha256,
    this.width,
    this.height,
  });

  final String id, type, codec, sha256;
  final int offset, packedBytes, unpackedBytes;
  final int? width, height;

  Map<String, Object> toJson() => {
    'id': id,
    'type': type,
    'offset': offset,
    'packedBytes': packedBytes,
    'unpackedBytes': unpackedBytes,
    'codec': codec,
    'sha256': sha256,
    if (width != null) 'width': width!,
    if (height != null) 'height': height!,
  };
}
