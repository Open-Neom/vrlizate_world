import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:vrlizate_world/vrlizate_world.dart';

void main() {
  final plaza = VrWorldAddress(
    worldId: 'vrlizate.plaza',
    instanceId: 'public-1',
  );
  VrWorldEntity tree(String id, double x, double y, double z) => VrWorldEntity(
    id: id,
    prototypeId: 'tree.oak',
    world: plaza,
    transform: VrWorldTransform(position: VrWorldPosition(x, y, z)),
  );

  test('world addresses isolate instances and validate identifiers', () {
    expect(
      plaza,
      VrWorldAddress(worldId: 'vrlizate.plaza', instanceId: 'public-1'),
    );
    expect(
      plaza,
      isNot(VrWorldAddress(worldId: 'vrlizate.plaza', instanceId: 'public-2')),
    );
    for (final id in ['', '../bad', 'space id', 'id\n', 'x' * 129]) {
      expect(
        () => VrWorldAddress(worldId: id, instanceId: 'one'),
        throwsArgumentError,
      );
    }
  });

  test('position and scale reject nonfinite or out-of-bounds values', () {
    for (final value in [double.nan, double.infinity, -double.infinity, 1e8]) {
      expect(() => VrWorldPosition(value, 0, 0), throwsArgumentError);
      expect(() => VrWorldPosition(0, value, 0), throwsArgumentError);
      expect(() => VrWorldPosition(0, 0, value), throwsArgumentError);
    }
    for (final scale in [0.0, -1.0, double.infinity, double.nan, 1001.0]) {
      expect(
        () => VrWorldTransform(position: VrWorldPosition.zero, scale: scale),
        throwsArgumentError,
      );
    }
    expect(
      () => VrWorldTransform(
        position: VrWorldPosition.zero,
        yawRadians: double.nan,
      ),
      throwsArgumentError,
    );
  });

  test(
    'prototype positions transform consistently with Y-up right-handed yaw',
    () {
      final placement = VrWorldTransform(
        position: VrWorldPosition(10, 2, -4),
        yawRadians: math.pi / 2,
        scale: 2,
      );
      final tip = placement.transformPoint(VrWorldPosition(0, 1, -1));
      expect(tip.x, closeTo(8, 1e-9));
      expect(tip.y, 4);
      expect(tip.z, closeTo(-4, 1e-9));
      expect(placement.copyWith(position: VrWorldPosition.zero).scale, 2);
    },
  );

  test('add rejects duplicate IDs, wrong instances, and excess capacity', () {
    final registry = VrWorldRegistry(world: plaza, maxEntities: 1);
    final first = tree('oak-1', 0, 0, 0);
    registry.add(first);
    expect(registry['oak-1'], same(first));
    expect(() => registry.add(first), throwsStateError);
    expect(() => registry.add(tree('oak-2', 1, 0, 0)), throwsStateError);
    expect(
      () => registry.add(
        VrWorldEntity(
          id: 'foreign',
          prototypeId: 'tree.oak',
          world: VrWorldAddress(worldId: 'vrlizate.plaza', instanceId: 'other'),
          transform: first.transform,
        ),
      ),
      throwsArgumentError,
    );
    expect(registry.length, 1);
  });

  test('prototype and entity IDs cannot be paths or oversized payloads', () {
    expect(
      () => VrWorldEntity(
        id: 'oak',
        prototypeId: 'https://server/script.dart',
        world: plaza,
        transform: VrWorldTransform(position: VrWorldPosition.zero),
      ),
      throwsArgumentError,
    );
    expect(() => tree('../outside', 0, 0, 0), throwsArgumentError);
  });

  test(
    'radius query crosses negative cell boundaries using full 3D distance',
    () {
      final registry = VrWorldRegistry(world: plaza, cellSizeMeters: 10);
      registry
        ..add(tree('left', -10.1, 0, -.1))
        ..add(tree('right', -9.9, 0, .1))
        ..add(tree('above', -10, 2, 0))
        ..add(tree('distant', 10, 0, 0));
      // Add enough distant entities to exercise the cell-query path, not fallback.
      for (var i = 0; i < 12; i++) {
        registry.add(tree('far-$i', 100 + i.toDouble(), 0, 100));
      }
      final near = registry.queryRadius(
        center: VrWorldPosition(-10, 0, 0),
        radiusMeters: .2,
      );
      expect(near.map((e) => e.id), unorderedEquals(['left', 'right']));
    },
  );

  test('radius includes exact boundary and zero-radius origins', () {
    final registry = VrWorldRegistry(world: plaza)
      ..add(tree('origin', 0, 0, 0))
      ..add(tree('edge', 3, 4, 0))
      ..add(tree('outside', 3, 4.01, 0));
    expect(
      registry
          .queryRadius(center: VrWorldPosition.zero, radiusMeters: 5)
          .map((e) => e.id),
      unorderedEquals(['origin', 'edge']),
    );
    expect(
      registry
          .queryRadius(center: VrWorldPosition.zero, radiusMeters: 0)
          .single
          .id,
      'origin',
    );
  });

  test('large finite queries remain bounded and retain exact filtering', () {
    final registry = VrWorldRegistry(world: plaza, cellSizeMeters: .1)
      ..add(tree('near', 0, 0, 0))
      ..add(tree('far', 1000000, 0, 0));
    expect(
      registry
          .queryRadius(center: VrWorldPosition.zero, radiusMeters: 500000)
          .single
          .id,
      'near',
    );
    expect(
      registry
          .queryRadius(center: VrWorldPosition.zero, radiusMeters: 1e300)
          .length,
      2,
    );
  });

  test(
    'update migrates cells, rejects missing/wrong-world writes atomically',
    () {
      final registry = VrWorldRegistry(world: plaza, cellSizeMeters: 2);
      final original = tree('moving', -3, 0, 0);
      registry.add(original);
      for (var i = 0; i < 8; i++) {
        registry.add(tree('far-$i', 20 + i.toDouble(), 0, 20));
      }
      registry.update(
        original.copyWith(
          transform: original.transform.copyWith(
            position: VrWorldPosition(3, 0, 0),
          ),
        ),
      );
      expect(
        registry.queryRadius(
          center: original.transform.position,
          radiusMeters: 0,
        ),
        isEmpty,
      );
      expect(
        registry
            .queryRadius(center: VrWorldPosition(3, 0, 0), radiusMeters: 0)
            .single
            .id,
        'moving',
      );
      expect(() => registry.update(tree('missing', 0, 0, 0)), throwsStateError);
      expect(
        () => registry.update(
          VrWorldEntity(
            id: 'moving',
            prototypeId: 'tree.oak',
            world: VrWorldAddress(worldId: 'another', instanceId: 'public-1'),
            transform: original.transform,
          ),
        ),
        throwsArgumentError,
      );
      expect(registry['moving']!.transform.position.x, 3);
      expect(original.transform.position.x, -3);
    },
  );

  test(
    'remove clears spatial entries, permits ID reuse, and clear releases all',
    () {
      final registry = VrWorldRegistry(world: plaza)..add(tree('oak', 0, 0, 0));
      expect(registry.remove('oak')!.id, 'oak');
      expect(registry.remove('oak'), isNull);
      registry.add(tree('oak', 0, 0, 0));
      expect(registry.length, 1);
      registry.clear();
      expect(registry.isEmpty, isTrue);
      expect(
        registry.queryRadius(center: VrWorldPosition.zero, radiusMeters: 10),
        isEmpty,
      );
    },
  );

  test('results and entity inventories are immutable snapshots', () {
    final registry = VrWorldRegistry(world: plaza)..add(tree('oak', 0, 0, 0));
    final snapshot = registry.entities;
    final nearby = registry.queryRadius(
      center: VrWorldPosition.zero,
      radiusMeters: 1,
    );
    expect(() => snapshot.clear(), throwsUnsupportedError);
    expect(() => nearby.clear(), throwsUnsupportedError);
    registry.remove('oak');
    expect(snapshot.single.id, 'oak');
    expect(nearby.single.id, 'oak');
  });

  test('registry validates query limits even when empty', () {
    final registry = VrWorldRegistry(world: plaza);
    for (final radius in [-1.0, double.nan, double.infinity]) {
      expect(
        () => registry.queryRadius(
          center: VrWorldPosition.zero,
          radiusMeters: radius,
        ),
        throwsArgumentError,
      );
    }
    for (final size in [0.0, .01, double.nan, double.infinity, 1e8]) {
      expect(
        () => VrWorldRegistry(world: plaza, cellSizeMeters: size),
        throwsArgumentError,
      );
    }
    for (final capacity in [0, -1, VrWorldRegistry.maximumEntityCapacity + 1]) {
      expect(
        () => VrWorldRegistry(world: plaza, maxEntities: capacity),
        throwsArgumentError,
      );
    }
  });

  test('spatial index agrees with brute-force distance across updates', () {
    final registry = VrWorldRegistry(world: plaza, cellSizeMeters: 4);
    final random = math.Random(42);
    for (var i = 0; i < 300; i++) {
      registry.add(
        tree(
          'entity-$i',
          random.nextDouble() * 200 - 100,
          random.nextDouble() * 20 - 10,
          random.nextDouble() * 200 - 100,
        ),
      );
    }
    for (var i = 0; i < 100; i++) {
      registry.update(
        tree(
          'entity-$i',
          random.nextDouble() * 200 - 100,
          random.nextDouble() * 20 - 10,
          random.nextDouble() * 200 - 100,
        ),
      );
    }
    for (var i = 0; i < 50; i++) {
      final center = VrWorldPosition(
        random.nextDouble() * 100 - 50,
        random.nextDouble() * 20 - 10,
        random.nextDouble() * 100 - 50,
      );
      final radius = random.nextDouble() * 30;
      final expected = registry.entities
          .where((e) => e.transform.position.distanceTo(center) <= radius)
          .map((e) => e.id);
      final actual = registry.queryRadius(center: center, radiusMeters: radius);
      expect(actual.map((e) => e.id), unorderedEquals(expected));
    }
  });
}
