import 'dart:convert';
import 'dart:math' as math;

import '../../utils/constants/vr_world_constants.dart';
import '../models/vr_shared_space_anchor.dart';
import '../models/vr_world_position.dart';
import '../models/vr_world_transform.dart';

/// Encodes and decodes [VrSharedSpaceAnchor] payloads to/from canonical
/// `vrlizate://space/...` URIs and compact `VRLZ-SPACE-...` share codes, and
/// aligns peer local coordinates into the shared world frame.
final class VrSharedSpaceCodec {
  const VrSharedSpaceCodec();

  /// Encodes [anchor] into a canonical `vrlizate://space/<worldId>/<anchorId>` URI.
  Uri toUri(VrSharedSpaceAnchor anchor) => Uri(
    scheme: VrWorldConstants.sharedSpaceUriScheme,
    host: VrWorldConstants.sharedSpaceUriHost,
    pathSegments: <String>[anchor.worldId, anchor.anchorId],
    queryParameters: <String, String>{
      VrWorldConstants.keyOriginX: anchor.originOffset.x.toString(),
      VrWorldConstants.keyOriginY: anchor.originOffset.y.toString(),
      VrWorldConstants.keyOriginZ: anchor.originOffset.z.toString(),
      VrWorldConstants.keyCompassHeadingDegrees: anchor.compassHeadingDegrees
          .toString(),
      VrWorldConstants.keyRoomWidthMeters: anchor.roomWidthMeters.toString(),
      VrWorldConstants.keyRoomDepthMeters: anchor.roomDepthMeters.toString(),
      VrWorldConstants.keyHostDisplayName: anchor.hostDisplayName,
      VrWorldConstants.keyCreatedAtEpochMs: anchor.createdAtEpochMs.toString(),
    },
  );

  /// Decodes and validates a `vrlizate://space/<worldId>/<anchorId>` URI.
  VrSharedSpaceAnchor fromUri(Uri uri) {
    if (uri.scheme != VrWorldConstants.sharedSpaceUriScheme ||
        uri.host != VrWorldConstants.sharedSpaceUriHost ||
        uri.pathSegments.length != 2) {
      throw FormatException(VrWorldConstants.errInvalidSharedSpaceUri, uri);
    }
    final worldId = uri.pathSegments[0];
    final anchorId = uri.pathSegments[1];
    final params = uri.queryParameters;

    final ox = double.tryParse(params[VrWorldConstants.keyOriginX] ?? '');
    final oy = double.tryParse(params[VrWorldConstants.keyOriginY] ?? '');
    final oz = double.tryParse(params[VrWorldConstants.keyOriginZ] ?? '');
    final heading = double.tryParse(
      params[VrWorldConstants.keyCompassHeadingDegrees] ?? '',
    );
    final rw = double.tryParse(
      params[VrWorldConstants.keyRoomWidthMeters] ?? '',
    );
    final rd = double.tryParse(
      params[VrWorldConstants.keyRoomDepthMeters] ?? '',
    );
    final host = params[VrWorldConstants.keyHostDisplayName];
    final ts = int.tryParse(params[VrWorldConstants.keyCreatedAtEpochMs] ?? '');

    if (ox == null ||
        oy == null ||
        oz == null ||
        heading == null ||
        rw == null ||
        rd == null ||
        host == null ||
        ts == null) {
      throw FormatException(VrWorldConstants.errInvalidSharedSpaceUri, uri);
    }

    try {
      return VrSharedSpaceAnchor(
        anchorId: anchorId,
        worldId: worldId,
        originOffset: VrWorldPosition(ox, oy, oz),
        compassHeadingDegrees: heading,
        roomWidthMeters: rw,
        roomDepthMeters: rd,
        hostDisplayName: host,
        createdAtEpochMs: ts,
      );
    } on ArgumentError catch (e) {
      throw FormatException(e.message.toString(), uri);
    }
  }

  /// Encodes [anchor] into a compact, URL-safe `VRLZ-SPACE-...` share code.
  String encodeShareCode(VrSharedSpaceAnchor anchor) {
    final jsonBytes = utf8.encode(jsonEncode(anchor.toJson()));
    final payload = base64Url.encode(jsonBytes).replaceAll('=', '');
    return '${VrWorldConstants.sharedSpaceCodePrefix}$payload';
  }

  /// Decodes a `VRLZ-SPACE-...` share code into a validated [VrSharedSpaceAnchor].
  VrSharedSpaceAnchor decodeShareCode(String shareCode) {
    final trimmed = shareCode.trim();
    if (!trimmed.startsWith(VrWorldConstants.sharedSpaceCodePrefix)) {
      throw const FormatException(VrWorldConstants.errInvalidSharedSpaceCode);
    }
    final rawPayload = trimmed.substring(
      VrWorldConstants.sharedSpaceCodePrefix.length,
    );
    if (rawPayload.isEmpty) {
      throw const FormatException(VrWorldConstants.errInvalidSharedSpaceCode);
    }
    try {
      final normalized = base64Url.normalize(rawPayload);
      final decodedText = utf8.decode(base64Url.decode(normalized));
      final decodedJson = jsonDecode(decodedText);
      if (decodedJson is! Map) {
        throw const FormatException(VrWorldConstants.errInvalidSharedSpaceCode);
      }
      return VrSharedSpaceAnchor.fromJson(
        Map<String, dynamic>.from(decodedJson),
      );
    } on FormatException {
      rethrow;
    } on ArgumentError catch (e) {
      throw FormatException(e.message.toString());
    } catch (_) {
      throw const FormatException(VrWorldConstants.errInvalidSharedSpaceCode);
    }
  }

  /// Converts [anchor] into a [VrWorldTransform] representing the shared space
  /// origin and heading inside the target world.
  VrWorldTransform toWorldTransform(VrSharedSpaceAnchor anchor) {
    final yawRadians =
        anchor.compassHeadingDegrees *
        (2 * math.pi / VrWorldConstants.fullCircleDegrees);
    return VrWorldTransform(
      position: anchor.originOffset,
      yawRadians: yawRadians,
    );
  }

  /// Transforms a peer's calibrated room-local position [peerLocalPos] into the
  /// shared world coordinate space defined by [anchor].
  VrWorldPosition alignPeerPosition(
    VrWorldPosition peerLocalPos,
    VrSharedSpaceAnchor anchor,
  ) => toWorldTransform(anchor).transformPoint(peerLocalPos);
}
