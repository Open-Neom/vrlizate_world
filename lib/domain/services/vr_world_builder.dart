import '../../utils/constants/vr_world_constants.dart';
import '../../utils/enums/vr_world_environment_preset.dart';
import '../models/vr_portal_link.dart';
import '../models/vr_world_address.dart';
import '../models/vr_world_entity.dart';
import '../models/vr_world_position.dart';
import '../models/vr_world_transform.dart';
import 'vr_world_registry.dart';

/// Fluent builder to programmatically construct a VRlizate world, add entities,
/// add portals, and populate a [VrWorldRegistry].
final class VrWorldBuilder {
  VrWorldBuilder({
    required this.world,
    this.environmentPreset = VrWorldEnvironmentPreset.daylight,
    this.cellSizeMeters = VrWorldConstants.defaultRegistryCellSizeMeters,
    this.maxEntities = VrWorldConstants.defaultRegistryMaxEntities,
  });

  factory VrWorldBuilder.forAddress({
    required String worldId,
    String instanceId = VrWorldConstants.defaultInstanceId,
    VrWorldEnvironmentPreset environmentPreset =
        VrWorldEnvironmentPreset.daylight,
    double cellSizeMeters = VrWorldConstants.defaultRegistryCellSizeMeters,
    int maxEntities = VrWorldConstants.defaultRegistryMaxEntities,
  }) => VrWorldBuilder(
    world: VrWorldAddress(worldId: worldId, instanceId: instanceId),
    environmentPreset: environmentPreset,
    cellSizeMeters: cellSizeMeters,
    maxEntities: maxEntities,
  );

  final VrWorldAddress world;
  VrWorldEnvironmentPreset environmentPreset;
  final double cellSizeMeters;
  final int maxEntities;

  final Map<String, VrWorldEntity> _entities = <String, VrWorldEntity>{};
  final Map<String, VrPortalLink> _portals = <String, VrPortalLink>{};

  List<VrWorldEntity> get entities => List.unmodifiable(_entities.values);
  List<VrPortalLink> get portals => List.unmodifiable(_portals.values);

  /// Sets the world's [VrWorldEnvironmentPreset] and returns this builder.
  VrWorldBuilder withEnvironmentPreset(VrWorldEnvironmentPreset preset) {
    environmentPreset = preset;
    return this;
  }

  /// Adds an existing [VrWorldEntity] belonging to [world].
  VrWorldBuilder addEntity(VrWorldEntity entity) {
    if (entity.world != world) {
      throw ArgumentError.value(
        entity.world,
        VrWorldConstants.paramWorld,
        VrWorldConstants.errDifferentWorldInstance,
      );
    }
    if (_entities.containsKey(entity.id)) {
      throw StateError('Entity ${entity.id} already exists.');
    }
    if (_entities.length >= maxEntities) {
      throw StateError(VrWorldConstants.errEntityCapacityReached);
    }
    _entities[entity.id] = entity;
    return this;
  }

  /// Places a new [VrWorldEntity] at [position] in [world] and returns this builder.
  VrWorldBuilder placeEntity({
    required String id,
    required String prototypeId,
    required VrWorldPosition position,
    double yawRadians = VrWorldConstants.defaultYawRadians,
    double scale = VrWorldConstants.defaultScale,
  }) => addEntity(
    VrWorldEntity(
      id: id,
      prototypeId: prototypeId,
      world: world,
      transform: VrWorldTransform(
        position: position,
        yawRadians: yawRadians,
        scale: scale,
      ),
    ),
  );

  /// Adds an existing [VrPortalLink] originating from [world].
  VrWorldBuilder addPortal(VrPortalLink portal) {
    if (portal.sourceWorld != world) {
      throw ArgumentError.value(
        portal.sourceWorld,
        VrWorldConstants.paramSourceWorld,
        VrWorldConstants.errDifferentWorldInstance,
      );
    }
    if (_portals.containsKey(portal.id)) {
      throw StateError('Portal ${portal.id} already exists.');
    }
    _portals[portal.id] = portal;
    return this;
  }

  /// Creates and registers a [VrPortalLink] originating from [world] to [targetWorld].
  VrWorldBuilder linkPortal({
    required String id,
    required VrWorldAddress targetWorld,
    required VrWorldPosition localPosition,
    double triggerRadiusMeters =
        VrWorldConstants.defaultPortalTriggerRadiusMeters,
    required String label,
  }) => addPortal(
    VrPortalLink(
      id: id,
      sourceWorld: world,
      targetWorld: targetWorld,
      localPosition: localPosition,
      triggerRadiusMeters: triggerRadiusMeters,
      label: label,
    ),
  );

  /// Returns the closest [VrPortalLink] triggered by [observerPosition], or `null`.
  VrPortalLink? findTriggeredPortal(VrWorldPosition observerPosition) {
    VrPortalLink? closest;
    var bestDistanceSquared = double.infinity;
    for (final portal in _portals.values) {
      if (portal.isTriggeredBy(observerPosition)) {
        final distSq = portal.localPosition.distanceSquaredTo(observerPosition);
        if (distSq < bestDistanceSquared) {
          bestDistanceSquared = distSq;
          closest = portal;
        }
      }
    }
    return closest;
  }

  /// Populates an existing [registry] with all entities in this builder.
  void populateRegistry(VrWorldRegistry registry) {
    if (registry.world != world) {
      throw ArgumentError.value(
        registry.world,
        VrWorldConstants.paramWorld,
        VrWorldConstants.errDifferentWorldInstance,
      );
    }
    for (final entity in _entities.values) {
      registry.add(entity);
    }
  }

  /// Builds and returns a new [VrWorldRegistry] populated with all entities.
  VrWorldRegistry buildRegistry() {
    final registry = VrWorldRegistry(
      world: world,
      cellSizeMeters: cellSizeMeters,
      maxEntities: maxEntities,
    );
    populateRegistry(registry);
    return registry;
  }
}
