/// A region's independently compressed and hashed payload.
/// [offset] is relative to [VrlwBundleHeader.payloadOffset].
final class VrlwChunkIndex {
  const VrlwChunkIndex({
    required this.x,
    required this.z,
    required this.offset,
    required this.packedBytes,
    required this.unpackedBytes,
    required this.codec,
    required this.sha256,
  });

  final int x;
  final int z;
  final int offset;
  final int packedBytes;
  final int unpackedBytes;
  final String codec;
  final String sha256;

  Map<String, Object> toJson() => {
    'x': x,
    'z': z,
    'offset': offset,
    'packedBytes': packedBytes,
    'unpackedBytes': unpackedBytes,
    'codec': codec,
    'sha256': sha256,
  };
}
