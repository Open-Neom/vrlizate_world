import '../../utils/constants/vr_world_constants.dart';

/// The fixed prefix of an experimental, indexed `.vrlw` world data bundle.
///
/// All offsets are bytes. The payload contains independent region chunks,
/// allowing transports to fetch the index and then only nearby regions.
final class VrlwBundleHeader {
  const VrlwBundleHeader(this.manifestLength, this.packedPayloadLength);

  final int manifestLength;
  final int packedPayloadLength;
  int get payloadOffset => VrWorldConstants.vrlwHeaderSize + manifestLength;
  int get totalLength => payloadOffset + packedPayloadLength;
}
