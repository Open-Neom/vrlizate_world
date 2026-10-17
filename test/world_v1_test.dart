import 'package:test/test.dart';
import 'package:vrlizate_world/vrlizate_world.dart';

void main() {
  group('VrWorldEnvironmentPreset', () {
    test('exposes all six standard presets', () {
      expect(
        VrWorldEnvironmentPreset.values,
        containsAll(<VrWorldEnvironmentPreset>[
          VrWorldEnvironmentPreset.daylight,
          VrWorldEnvironmentPreset.nightSky,
          VrWorldEnvironmentPreset.cyberpunkNeon,
          VrWorldEnvironmentPreset.studioNeutral,
          VrWorldEnvironmentPreset.sunsetHorizon,
          VrWorldEnvironmentPreset.deepSpace,
        ]),
      );
    });
  });

  group('VrPortalLink', () {
    test('detects when observer position is within trigger radius and validates fields', () {
      final source = VrWorldAddress(worldId: 'world.lobby', instanceId: 'local');
      final target = VrWorldAddress(worldId: 'world.stage', instanceId: 'main');
      final portal = VrPortalLink(
        id: 'portal.stage',
        sourceWorld: source,
        targetWorld: target,
        localPosition: VrWorldPosition(10, 0, -5),
        triggerRadiusMeters: 2.0,
        label: 'Main Stage',
      );

      expect(portal.isTriggeredBy(VrWorldPosition(11, 0, -5)), isTrue);
      expect(portal.isTriggeredBy(VrWorldPosition(15, 0, -5)), isFalse);
      expect(portal.distanceTo(VrWorldPosition(13, 0, -5)), closeTo(3.0, 1e-6));

      expect(
        () => VrPortalLink(
          id: 'same',
          sourceWorld: source,
          targetWorld: source,
          localPosition: VrWorldPosition.zero,
          label: 'Same World',
        ),
        throwsArgumentError,
      );
    });
  });

  group('VrWorldBuilder', () {
    test('fluently builds a registry, places entities, and resolves triggered portals', () {
      final world = VrWorldAddress(worldId: 'vrlizate.plaza', instanceId: 'room1');
      final targetWorld = VrWorldAddress(worldId: 'vrlizate.club', instanceId: 'local');
      final builder = VrWorldBuilder(
        world: world,
        environmentPreset: VrWorldEnvironmentPreset.cyberpunkNeon,
        cellSizeMeters: 32,
      )
        ..placeEntity(
          id: 'tree-1',
          prototypeId: 'prop.tree',
          position: VrWorldPosition(4, 0, 4),
        )
        ..linkPortal(
          id: 'portal-club',
          targetWorld: targetWorld,
          localPosition: VrWorldPosition(40, 0, 10),
          triggerRadiusMeters: 2.5,
          label: 'Neon Club',
        );

      expect(builder.environmentPreset, equals(VrWorldEnvironmentPreset.cyberpunkNeon));
      expect(builder.entities.length, equals(1));
      expect(builder.portals.length, equals(1));

      final triggered = builder.findTriggeredPortal(VrWorldPosition(41, 0, 10));
      expect(triggered, isNotNull);
      expect(triggered!.id, equals('portal-club'));
      expect(builder.findTriggeredPortal(VrWorldPosition(0, 0, 0)), isNull);

      final registry = builder.buildRegistry();
      expect(registry.length, equals(1));
      expect(registry['tree-1']?.prototypeId, equals('prop.tree'));
    });
  });
}
