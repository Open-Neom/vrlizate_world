import '../../utils/constants/vr_world_constants.dart';
import '../../utils/vr_world_validator.dart';
import 'vr_world_address.dart';
import 'vr_world_position.dart';

/// Represents a spatial portal linking a local position in [sourceWorld] to [targetWorld].
final class VrPortalLink {
  factory VrPortalLink({
    required String id,
    required VrWorldAddress sourceWorld,
    required VrWorldAddress targetWorld,
    required VrWorldPosition localPosition,
    double triggerRadiusMeters =
        VrWorldConstants.defaultPortalTriggerRadiusMeters,
    required String label,
  }) {
    VrWorldValidator.validateIdentifier(id, VrWorldConstants.paramId);
    if (sourceWorld == targetWorld) {
      throw ArgumentError.value(
        targetWorld,
        VrWorldConstants.paramTargetWorld,
        VrWorldConstants.errPortalSameWorld,
      );
    }
    if (!triggerRadiusMeters.isFinite ||
        triggerRadiusMeters <= 0 ||
        triggerRadiusMeters > VrWorldConstants.maxPortalTriggerRadiusMeters) {
      throw ArgumentError.value(
        triggerRadiusMeters,
        VrWorldConstants.paramTriggerRadiusMeters,
        VrWorldConstants.errPortalTriggerRadius,
      );
    }
    final trimmedLabel = label.trim();
    if (trimmedLabel.isEmpty ||
        trimmedLabel.length > VrWorldConstants.maxPortalLabelLength) {
      throw ArgumentError.value(
        label,
        VrWorldConstants.paramLabel,
        VrWorldConstants.errPortalLabel,
      );
    }
    return VrPortalLink._(
      id,
      sourceWorld,
      targetWorld,
      localPosition,
      triggerRadiusMeters,
      trimmedLabel,
    );
  }

  const VrPortalLink._(
    this.id,
    this.sourceWorld,
    this.targetWorld,
    this.localPosition,
    this.triggerRadiusMeters,
    this.label,
  );

  final String id;
  final VrWorldAddress sourceWorld;
  final VrWorldAddress targetWorld;
  final VrWorldPosition localPosition;
  final double triggerRadiusMeters;
  final String label;

  /// Returns `true` when [observerPosition] lies within [triggerRadiusMeters] of [localPosition].
  bool isTriggeredBy(VrWorldPosition observerPosition) =>
      localPosition.distanceSquaredTo(observerPosition) <=
      triggerRadiusMeters * triggerRadiusMeters;

  /// Returns the Euclidean distance in meters from [observerPosition] to [localPosition].
  double distanceTo(VrWorldPosition observerPosition) =>
      localPosition.distanceTo(observerPosition);

  @override
  bool operator ==(Object other) =>
      other is VrPortalLink &&
      id == other.id &&
      sourceWorld == other.sourceWorld &&
      targetWorld == other.targetWorld &&
      localPosition == other.localPosition &&
      triggerRadiusMeters == other.triggerRadiusMeters &&
      label == other.label;

  @override
  int get hashCode => Object.hash(
    id,
    sourceWorld,
    targetWorld,
    localPosition,
    triggerRadiusMeters,
    label,
  );
}
