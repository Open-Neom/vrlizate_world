import 'dart:math' as math;

import '../../utils/constants/vr_world_constants.dart';

/// Immutable coordinates in meters: +X right, +Y up, -Z forward.
///
/// Each instance has a local origin. The explicit coordinate bound keeps grid
/// arithmetic portable and prevents untrusted values from creating enormous
/// cell indices. Larger universes should use separate world instances/origins.
final class VrWorldPosition {
  factory VrWorldPosition(double x, double y, double z) {
    // Coordinate samples need no temporary list or records for validation.
    _validateCoordinate(x, 'x');
    _validateCoordinate(y, 'y');
    _validateCoordinate(z, 'z');
    return VrWorldPosition._(x, y, z);
  }

  static void _validateCoordinate(double value, String name) {
    if (!value.isFinite || value.abs() > maximumCoordinateMeters) {
      throw ArgumentError.value(
        value,
        name,
        VrWorldConstants.errCoordinateOutOfBounds,
      );
    }
  }

  const VrWorldPosition._(this.x, this.y, this.z);

  static const zero = VrWorldPosition._(0, 0, 0);
  static const maximumCoordinateMeters =
      VrWorldConstants.maximumCoordinateMeters;

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
