import 'package:test/test.dart';
import 'package:vrlizate_world/vrlizate_world.dart';

void main() {
  group('VrSharedSpaceCodec & VrSharedSpaceAnchor (P2P Co-Located Spaces)', () {
    test('encodes and decodes canonical vrlizate://space URI and share code', () {
      const codec = VrSharedSpaceCodec();
      final anchor = VrSharedSpaceAnchor(
        anchorId: 'room_alpha_01',
        worldId: 'mall_central',
        originOffset: VrWorldPosition(1.25, 0.0, -2.5),
        compassHeadingDegrees: 90.0,
        roomWidthMeters: 3.5,
        roomDepthMeters: 4.2,
        hostDisplayName: 'Serzen Host',
        createdAtEpochMs: 1730000000000,
      );

      final uri = codec.toUri(anchor);
      expect(uri.scheme, 'vrlizate');
      expect(uri.host, 'space');

      final fromUri = codec.fromUri(uri);
      expect(fromUri, equals(anchor));

      final shareCode = codec.encodeShareCode(anchor);
      expect(shareCode, startsWith(VrWorldConstants.sharedSpaceCodePrefix));

      final fromCode = codec.decodeShareCode(shareCode);
      expect(fromCode, equals(anchor));
    });

    test('aligns peer local coordinates into shared space origin and heading', () {
      const codec = VrSharedSpaceCodec();
      final anchor = VrSharedSpaceAnchor(
        anchorId: 'room_beta_02',
        worldId: 'arcade_hall',
        originOffset: VrWorldPosition(10.0, 0.0, 5.0),
        compassHeadingDegrees: 90.0,
        hostDisplayName: 'Peer Host',
      );

      final aligned = codec.alignPeerPosition(
        VrWorldPosition(0.0, 1.6, -2.0),
        anchor,
      );

      expect(aligned.y, closeTo(1.6, 1e-6));
      expect(aligned.x, closeTo(8.0, 1e-5));
      expect(aligned.z, closeTo(5.0, 1e-5));
    });
  });
}
