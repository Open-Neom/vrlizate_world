import 'dart:math' as math;

import 'world_address.dart';

/// Immutable coordinates in meters: +X right, +Y up, -Z forward.
///
/// Each instance has a local origin. The explicit coordinate bound keeps grid
/// arithmetic portable and prevents untrusted values from creating enormous
/// cell indices. Larger universes should use separate world instances/origins.
final class VrWorldPosition {
  factory VrWorldPosition(double x, double y, double z) {
    for (final (name, value) in [('x', x), ('y', y), ('z', z)]) {
      if (!value.isFinite || value.abs() > maximumCoordinateMeters) {
        throw ArgumentError.value(
          value,
          name,
          'Coordinate outside world bounds.',
        );
      }
    }
    return VrWorldPosition._(x, y, z);
  }

  const VrWorldPosition._(this.x, this.y, this.z);

  static const zero = VrWorldPosition._(0, 0, 0);
  static const maximumCoordinateMeters = 10000000.0;

  final double x;
  final double y;
  final double z;

  double distanceSquaredTo(VrWorldPosition other) {
    final dx = x - other.x;
    final dy = y - other.y;
    final dz = z - other.z;
    return dx * dx + dy * dy + dz * dz;
  }

  double distanceTo(VrWorldPosition other) =>
      math.sqrt(distanceSquaredTo(other));

  @override
  bool operator ==(Object other) =>
      other is VrWorldPosition && x == other.x && y == other.y && z == other.z;

  @override
  int get hashCode => Object.hash(x, y, z);
}

/// Position plus a Y-axis rotation in radians and a positive uniform scale.
/// Scale affects the prototype's dimensions; it does not change position units.
final class VrWorldTransform {
  factory VrWorldTransform({
    required VrWorldPosition position,
    double yawRadians = 0,
    double scale = 1,
  }) {
    if (!yawRadians.isFinite) {
      throw ArgumentError.value(yawRadians, 'yawRadians', 'Must be finite.');
    }
    if (!scale.isFinite || scale <= 0 || scale > maximumScale) {
      throw ArgumentError.value(
        scale,
        'scale',
        'Must be positive and <= 1000.',
      );
    }
    // Normalize equivalent rotations to a compact, consistent representation.
    final normalized = (yawRadians + math.pi) % (2 * math.pi) - math.pi;
    return VrWorldTransform._(position, normalized, scale);
  }

  const VrWorldTransform._(this.position, this.yawRadians, this.scale);

  static const maximumScale = 1000.0;
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

/// Stable entity identity and a renderer-owned prototype reference.
///
/// A prototype ID selects an explicitly registered factory, not executable code
/// or an arbitrary downloaded path. No mutable renderer or account is retained.
final class VrWorldEntity {
  factory VrWorldEntity({
    required String id,
    required String prototypeId,
    required VrWorldAddress world,
    required VrWorldTransform transform,
  }) {
    validateWorldIdentifier(id, 'id');
    validateWorldIdentifier(prototypeId, 'prototypeId');
    return VrWorldEntity._(id, prototypeId, world, transform);
  }

  const VrWorldEntity._(this.id, this.prototypeId, this.world, this.transform);

  final String id;
  final String prototypeId;
  final VrWorldAddress world;
  final VrWorldTransform transform;

  VrWorldEntity copyWith({VrWorldTransform? transform}) => VrWorldEntity(
    id: id,
    prototypeId: prototypeId,
    world: world,
    transform: transform ?? this.transform,
  );
}
