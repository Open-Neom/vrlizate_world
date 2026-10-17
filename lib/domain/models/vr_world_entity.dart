import '../../utils/constants/vr_world_constants.dart';
import '../../utils/vr_world_validator.dart';
import 'vr_world_address.dart';
import 'vr_world_transform.dart';

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
    VrWorldValidator.validateIdentifier(id, VrWorldConstants.paramId);
    VrWorldValidator.validateIdentifier(
      prototypeId,
      VrWorldConstants.paramPrototypeId,
    );
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
