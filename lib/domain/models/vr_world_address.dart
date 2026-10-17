import '../../utils/constants/vr_world_constants.dart';
import '../../utils/vr_world_validator.dart';

/// One independently populated instance of a world.
///
/// Two visitors share a coordinate space only when BOTH IDs match. IDs are
/// opaque stable identifiers, never physical GPS coordinates or user identity.
final class VrWorldAddress {
  factory VrWorldAddress({
    required String worldId,
    required String instanceId,
  }) {
    VrWorldValidator.validateIdentifier(worldId, VrWorldConstants.paramWorldId);
    VrWorldValidator.validateIdentifier(
      instanceId,
      VrWorldConstants.paramInstanceId,
    );
    return VrWorldAddress._(worldId, instanceId);
  }

  const VrWorldAddress._(this.worldId, this.instanceId);

  final String worldId;
  final String instanceId;

  @override
  bool operator ==(Object other) =>
      other is VrWorldAddress &&
      worldId == other.worldId &&
      instanceId == other.instanceId;

  @override
  int get hashCode => Object.hash(worldId, instanceId);

  @override
  String toString() => '$worldId@$instanceId';
}
