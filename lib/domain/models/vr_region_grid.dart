import '../../utils/constants/vr_world_constants.dart';
import '../../utils/vr_world_validator.dart';
import 'vr_region_key.dart';
import 'vr_world_address.dart';
import 'vr_world_position.dart';

/// Stable, bounded local X/Z cells. +Y height does not change horizontal region.
final class VrRegionGrid {
  VrRegionGrid({
    required this.world,
    required this.gridId,
    this.cellSizeMeters = VrWorldConstants.defaultRegionGridCellSizeMeters,
  }) {
    VrWorldValidator.validateIdentifier(gridId, VrWorldConstants.paramGridId);
    if (!cellSizeMeters.isFinite ||
        cellSizeMeters < VrWorldConstants.minCellSizeMeters ||
        cellSizeMeters > VrWorldPosition.maximumCoordinateMeters) {
      throw ArgumentError.value(
        cellSizeMeters,
        VrWorldConstants.paramCellSizeMeters,
      );
    }
  }

  final VrWorldAddress world;
  final String gridId;
  final double cellSizeMeters;

  VrRegionKey key(int x, int z) =>
      VrRegionKey(world: world, gridId: gridId, x: x, z: z);

  VrRegionKey keyAt(VrWorldPosition position) => key(
    (position.x / cellSizeMeters).floor(),
    (position.z / cellSizeMeters).floor(),
  );
}
