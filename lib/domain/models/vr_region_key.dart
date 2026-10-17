import 'dart:convert';

import '../../utils/constants/vr_world_constants.dart';
import '../../utils/vr_world_validator.dart';
import 'vr_world_address.dart';

/// A horizontal region in an explicitly named coordinate frame and revision.
///
/// [gridId] must identify the origin, axes, cell resolution and content revision.
/// Reusing an ID after rebasing an Earth frame or changing content would alias
/// different data. A geographic tile scheme can instead supply stable tile
/// coordinates through its own provider. This local grid is not a whole-planet
/// projection.
final class VrRegionKey {
  VrRegionKey({
    required this.world,
    required this.gridId,
    required this.x,
    required this.z,
  }) {
    VrWorldValidator.validateIdentifier(gridId, VrWorldConstants.paramGridId);
    if (x.abs() > VrWorldConstants.maxRegionGridIndex ||
        z.abs() > VrWorldConstants.maxRegionGridIndex) {
      throw ArgumentError(VrWorldConstants.errRegionIndexOutOfBounds);
    }
  }

  final VrWorldAddress world;
  final String gridId;
  final int x;
  final int z;

  /// Canonical identity suitable for hashing by a persistent byte-store adapter.
  /// This is not a filesystem path, URL, authorization token, or geographic GPS.
  String get cacheKey =>
      jsonEncode([world.worldId, world.instanceId, gridId, x, z]);

  @override
  bool operator ==(Object other) =>
      other is VrRegionKey &&
      world == other.world &&
      gridId == other.gridId &&
      x == other.x &&
      z == other.z;

  @override
  int get hashCode => Object.hash(world, gridId, x, z);

  @override
  String toString() => cacheKey;
}
