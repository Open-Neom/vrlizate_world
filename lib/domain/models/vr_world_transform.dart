import 'dart:math' as math;

import '../../utils/constants/vr_world_constants.dart';
import 'vr_world_position.dart';

/// Position plus a Y-axis rotation in radians and a positive uniform scale.
/// Scale affects the prototype's dimensions; it does not change position units.
final class VrWorldTransform {
  factory VrWorldTransform({
    required VrWorldPosition position,
    double yawRadians = VrWorldConstants.defaultYawRadians,
    double scale = VrWorldConstants.defaultScale,
  }) {
    if (!yawRadians.isFinite) {
      throw ArgumentError.value(
        yawRadians,
        VrWorldConstants.paramYawRadians,
        VrWorldConstants.errFinite,
      );
    }
    if (!scale.isFinite || scale <= 0 || scale > maximumScale) {
      throw ArgumentError.value(
        scale,
        VrWorldConstants.paramScale,
        VrWorldConstants.errScaleRange,
      );
    }
    // Normalize equivalent rotations to a compact, consistent representation.
    final normalized = (yawRadians + math.pi) % (2 * math.pi) - math.pi;
    return VrWorldTransform._(position, normalized, scale);
  }

  const VrWorldTransform._(this.position, this.yawRadians, this.scale);

  static const maximumScale = VrWorldConstants.maximumScale;
  final VrWorldPosition position;
  final double yawRadians;
  final double scale;

  VrWorldTransform copyWith({
    VrWorldPosition? position,
    double? yawRadians,
    double? scale,
  }) => VrWorldTransform(
    position: position ?? this.position,
    yawRadians: yawRadians ?? this.yawRadians,
    scale: scale ?? this.scale,
  );

  /// Transforms a point authored in the prototype's local coordinates.
  /// Collision and rendering can both consume the same placement.
  VrWorldPosition transformPoint(VrWorldPosition local) {
    final c = math.cos(yawRadians);
    final s = math.sin(yawRadians);
    return VrWorldPosition(
      position.x + scale * (c * local.x + s * local.z),
      position.y + scale * local.y,
      position.z + scale * (-s * local.x + c * local.z),
    );
  }
}
