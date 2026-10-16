import 'world_address.dart';
import 'world_entity.dart';

typedef _Cell = (int, int);

/// A bounded local registry for one world instance, indexed in X/Z cells.
///
/// Queries use full three-dimensional distance to each entity's origin. This is
/// an interest-management building block, not mesh visibility, collision,
/// network synchronization, or authorization. Query results are immutable
/// snapshots and make no ordering guarantee.
final class VrWorldRegistry {
  VrWorldRegistry({
    required this.world,
    this.cellSizeMeters = 16,
    this.maxEntities = 10000,
  }) {
    if (!cellSizeMeters.isFinite ||
        cellSizeMeters < 0.1 ||
        cellSizeMeters > VrWorldPosition.maximumCoordinateMeters) {
      throw ArgumentError.value(
        cellSizeMeters,
        'cellSizeMeters',
        'Must be finite, >= 0.1 and within world bounds.',
      );
    }
    if (maxEntities < 1 || maxEntities > maximumEntityCapacity) {
      throw ArgumentError.value(
        maxEntities,
        'maxEntities',
        'Must be between 1 and $maximumEntityCapacity.',
      );
    }
  }

  static const maximumEntityCapacity = 100000;
  static const _maximumQueryCells = 4096;
  final VrWorldAddress world;
  final double cellSizeMeters;
  final int maxEntities;
  final _entities = <String, VrWorldEntity>{};
  final _cells = <_Cell, Set<String>>{};

  int get length => _entities.length;
  bool get isEmpty => _entities.isEmpty;
  List<VrWorldEntity> get entities => List.unmodifiable(_entities.values);
  VrWorldEntity? operator [](String id) => _entities[id];

  void add(VrWorldEntity entity) {
    _validateWorld(entity);
    if (_entities.containsKey(entity.id)) {
      throw StateError('Entity ${entity.id} already exists.');
    }
    if (_entities.length >= maxEntities) {
      throw StateError('World entity capacity reached.');
    }
    _entities[entity.id] = entity;
    _index(entity);
  }

  /// Replaces an existing entity snapshot without changing its stable identity.
  void update(VrWorldEntity entity) {
    _validateWorld(entity);
    final previous = _entities[entity.id];
    if (previous == null) {
      throw StateError('Entity ${entity.id} does not exist.');
    }
    _unindex(previous);
    _entities[entity.id] = entity;
    _index(entity);
  }

  VrWorldEntity? remove(String id) {
    final previous = _entities.remove(id);
    if (previous != null) _unindex(previous);
    return previous;
  }

  void clear() {
    _entities.clear();
    _cells.clear();
  }

  List<VrWorldEntity> queryRadius({
    required VrWorldPosition center,
    required double radiusMeters,
  }) {
    if (!radiusMeters.isFinite || radiusMeters < 0) {
      throw ArgumentError.value(
        radiusMeters,
        'radiusMeters',
        'Must be finite and >= 0.',
      );
    }
    if (_entities.isEmpty) return const [];
    // Beyond the world's maximum diagonal, all positions are inside. Besides
    // being faster, this avoids large cell arithmetic and squared overflow.
    if (radiusMeters >= 4 * VrWorldPosition.maximumCoordinateMeters) {
      return entities;
    }
    final minX = ((center.x - radiusMeters) / cellSizeMeters).floor();
    final maxX = ((center.x + radiusMeters) / cellSizeMeters).floor();
    final minZ = ((center.z - radiusMeters) / cellSizeMeters).floor();
    final maxZ = ((center.z + radiusMeters) / cellSizeMeters).floor();
    final width = maxX - minX + 1;
    final depth = maxZ - minZ + 1;
    final radiusSquared = radiusMeters * radiusMeters;
    final result = <VrWorldEntity>[];
    void include(VrWorldEntity entity) {
      if (entity.transform.position.distanceSquaredTo(center) <=
          radiusSquared) {
        result.add(entity);
      }
    }

    // Large searches scan only stored entities. Never enumerate an unbounded
    // grid (even when a finite but unreasonable radius came from outside).
    if (width > _maximumQueryCells ||
        depth > _maximumQueryCells ||
        width * depth > _maximumQueryCells ||
        width * depth > _entities.length) {
      for (final entity in _entities.values) {
        include(entity);
      }
    } else {
      for (var x = minX; x <= maxX; x++) {
        for (var z = minZ; z <= maxZ; z++) {
          for (final id in _cells[(x, z)] ?? const <String>{}) {
            include(_entities[id]!);
          }
        }
      }
    }
    return List.unmodifiable(result);
  }

  void _validateWorld(VrWorldEntity entity) {
    if (entity.world != world) {
      throw ArgumentError.value(
        entity.world,
        'world',
        'Different world instance.',
      );
    }
  }

  _Cell _cell(VrWorldPosition position) => (
    (position.x / cellSizeMeters).floor(),
    (position.z / cellSizeMeters).floor(),
  );

  void _index(VrWorldEntity entity) => _cells
      .putIfAbsent(_cell(entity.transform.position), () => <String>{})
      .add(entity.id);

  void _unindex(VrWorldEntity entity) {
    final cell = _cell(entity.transform.position);
    final ids = _cells[cell]!;
    ids.remove(entity.id);
    if (ids.isEmpty) _cells.remove(cell);
  }
}
