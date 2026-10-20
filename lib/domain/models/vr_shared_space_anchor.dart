import '../../utils/constants/vr_world_constants.dart';
import '../../utils/vr_world_validator.dart';
import 'vr_world_position.dart';

/// Calibrated physical-to-virtual room anchor for peer-to-peer co-located VR
/// experiences without cloud servers.
///
/// Allows two or more users in the same room (or linked via P2P / QR code) to
/// align their local coordinate origins, compass heading, and room guardian
/// dimensions inside a shared [worldId].
final class VrSharedSpaceAnchor {
  factory VrSharedSpaceAnchor({
    required String anchorId,
    required String worldId,
    VrWorldPosition originOffset = VrWorldPosition.zero,
    double compassHeadingDegrees = 0.0,
    double roomWidthMeters = VrWorldConstants.defaultRoomWidthMeters,
    double roomDepthMeters = VrWorldConstants.defaultRoomDepthMeters,
    required String hostDisplayName,
    int createdAtEpochMs = 0,
  }) {
    VrWorldValidator.validateIdentifier(
      anchorId,
      VrWorldConstants.paramAnchorId,
    );
    VrWorldValidator.validateIdentifier(worldId, VrWorldConstants.paramWorldId);
    if (!compassHeadingDegrees.isFinite) {
      throw ArgumentError.value(
        compassHeadingDegrees,
        VrWorldConstants.paramCompassHeadingDegrees,
        VrWorldConstants.errFinite,
      );
    }
    if (!roomWidthMeters.isFinite ||
        roomWidthMeters < VrWorldConstants.minRoomDimensionMeters ||
        roomWidthMeters > VrWorldConstants.maxRoomDimensionMeters) {
      throw ArgumentError.value(
        roomWidthMeters,
        VrWorldConstants.paramRoomWidthMeters,
        VrWorldConstants.errRoomDimensionRange,
      );
    }
    if (!roomDepthMeters.isFinite ||
        roomDepthMeters < VrWorldConstants.minRoomDimensionMeters ||
        roomDepthMeters > VrWorldConstants.maxRoomDimensionMeters) {
      throw ArgumentError.value(
        roomDepthMeters,
        VrWorldConstants.paramRoomDepthMeters,
        VrWorldConstants.errRoomDimensionRange,
      );
    }
    final trimmedHost = hostDisplayName.trim();
    if (trimmedHost.isEmpty ||
        trimmedHost.length > VrWorldConstants.maxHostDisplayNameLength ||
        RegExp(VrWorldConstants.controlCharPattern).hasMatch(trimmedHost)) {
      throw ArgumentError.value(
        hostDisplayName,
        VrWorldConstants.paramHostDisplayName,
        VrWorldConstants.errHostDisplayName,
      );
    }
    if (createdAtEpochMs < 0) {
      throw ArgumentError.value(
        createdAtEpochMs,
        VrWorldConstants.paramCreatedAtEpochMs,
        VrWorldConstants.errCreatedAtEpochMs,
      );
    }

    final normalizedHeading =
        ((compassHeadingDegrees % VrWorldConstants.fullCircleDegrees) +
            VrWorldConstants.fullCircleDegrees) %
        VrWorldConstants.fullCircleDegrees;

    return VrSharedSpaceAnchor._(
      anchorId: anchorId,
      worldId: worldId,
      originOffset: originOffset,
      compassHeadingDegrees: normalizedHeading,
      roomWidthMeters: roomWidthMeters,
      roomDepthMeters: roomDepthMeters,
      hostDisplayName: trimmedHost,
      createdAtEpochMs: createdAtEpochMs,
    );
  }

  const VrSharedSpaceAnchor._({
    required this.anchorId,
    required this.worldId,
    required this.originOffset,
    required this.compassHeadingDegrees,
    required this.roomWidthMeters,
    required this.roomDepthMeters,
    required this.hostDisplayName,
    required this.createdAtEpochMs,
  });

  final String anchorId;
  final String worldId;
  final VrWorldPosition originOffset;
  final double compassHeadingDegrees;
  final double roomWidthMeters;
  final double roomDepthMeters;
  final String hostDisplayName;
  final int createdAtEpochMs;

  Map<String, Object?> toJson() => <String, Object?>{
    VrWorldConstants.keyAnchorId: anchorId,
    VrWorldConstants.keyWorldId: worldId,
    VrWorldConstants.keyOriginX: originOffset.x,
    VrWorldConstants.keyOriginY: originOffset.y,
    VrWorldConstants.keyOriginZ: originOffset.z,
    VrWorldConstants.keyCompassHeadingDegrees: compassHeadingDegrees,
    VrWorldConstants.keyRoomWidthMeters: roomWidthMeters,
    VrWorldConstants.keyRoomDepthMeters: roomDepthMeters,
    VrWorldConstants.keyHostDisplayName: hostDisplayName,
    VrWorldConstants.keyCreatedAtEpochMs: createdAtEpochMs,
  };

  factory VrSharedSpaceAnchor.fromJson(Map<String, dynamic> json) {
    final anchorId = json[VrWorldConstants.keyAnchorId];
    final worldId = json[VrWorldConstants.keyWorldId];
    final ox = json[VrWorldConstants.keyOriginX];
    final oy = json[VrWorldConstants.keyOriginY];
    final oz = json[VrWorldConstants.keyOriginZ];
    final heading = json[VrWorldConstants.keyCompassHeadingDegrees];
    final rw = json[VrWorldConstants.keyRoomWidthMeters];
    final rd = json[VrWorldConstants.keyRoomDepthMeters];
    final host = json[VrWorldConstants.keyHostDisplayName];
    final ts = json[VrWorldConstants.keyCreatedAtEpochMs];

    if (anchorId is! String ||
        worldId is! String ||
        ox is! num ||
        oy is! num ||
        oz is! num ||
        heading is! num ||
        rw is! num ||
        rd is! num ||
        host is! String ||
        ts is! int) {
      throw const FormatException(VrWorldConstants.errInvalidSharedSpaceCode);
    }

    return VrSharedSpaceAnchor(
      anchorId: anchorId,
      worldId: worldId,
      originOffset: VrWorldPosition(
        ox.toDouble(),
        oy.toDouble(),
        oz.toDouble(),
      ),
      compassHeadingDegrees: heading.toDouble(),
      roomWidthMeters: rw.toDouble(),
      roomDepthMeters: rd.toDouble(),
      hostDisplayName: host,
      createdAtEpochMs: ts,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VrSharedSpaceAnchor &&
          anchorId == other.anchorId &&
          worldId == other.worldId &&
          originOffset == other.originOffset &&
          compassHeadingDegrees == other.compassHeadingDegrees &&
          roomWidthMeters == other.roomWidthMeters &&
          roomDepthMeters == other.roomDepthMeters &&
          hostDisplayName == other.hostDisplayName &&
          createdAtEpochMs == other.createdAtEpochMs;

  @override
  int get hashCode => Object.hash(
    anchorId,
    worldId,
    originOffset,
    compassHeadingDegrees,
    roomWidthMeters,
    roomDepthMeters,
    hostDisplayName,
    createdAtEpochMs,
  );

  @override
  String toString() =>
      'VrSharedSpaceAnchor(anchorId: $anchorId, worldId: $worldId, '
      'heading: $compassHeadingDegrees, room: ${roomWidthMeters}x$roomDepthMeters)';
}
