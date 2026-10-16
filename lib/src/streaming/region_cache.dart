import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../world_address.dart';
import '../world_entity.dart';

/// A horizontal region in an explicitly named coordinate frame and revision.
///
/// [gridId] must identify the origin, axes, cell resolution and content revision.
/// Reusing an ID
/// after rebasing an Earth frame or changing content would alias different data.
/// A geographic tile scheme can instead supply stable tile coordinates through
/// its own provider. This local grid is not a whole-planet projection.
final class VrRegionKey {
  VrRegionKey({
    required this.world,
    required this.gridId,
    required this.x,
    required this.z,
  }) {
    validateWorldIdentifier(gridId, 'gridId');
    if (x.abs() > 100000016 || z.abs() > 100000016) {
      throw ArgumentError('Region index outside supported local grid bounds.');
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

/// Stable, bounded local X/Z cells. +Y height does not change horizontal region.
final class VrRegionGrid {
  VrRegionGrid({
    required this.world,
    required this.gridId,
    this.cellSizeMeters = 64,
  }) {
    validateWorldIdentifier(gridId, 'gridId');
    if (!cellSizeMeters.isFinite ||
        cellSizeMeters < 0.1 ||
        cellSizeMeters > VrWorldPosition.maximumCoordinateMeters) {
      throw ArgumentError.value(cellSizeMeters, 'cellSizeMeters');
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

/// Resident decoded data, independent of meshes, textures, or active rendering.
///
/// [sizeBytes] must conservatively account for decoded resident memory, not just
/// compressed transfer size. Hosts own actual resource measurement and release.
final class VrRegionData<T> {
  VrRegionData({required this.value, required this.sizeBytes}) {
    if (sizeBytes < 0 || sizeBytes > 2147483647) {
      throw ArgumentError.value(sizeBytes, 'sizeBytes');
    }
  }

  final T value;
  final int sizeBytes;
}

/// Cooperative cancellation. Providers should cancel their own network request
/// when possible. Ignored cancellation still discards the eventual result.
final class VrRegionCancellation {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;

  void throwIfCancelled() {
    if (_isCancelled) throw const VrRegionLoadCancelled();
  }
}

final class VrRegionLoadCancelled implements Exception {
  const VrRegionLoadCancelled();

  @override
  String toString() => 'Region request cancelled.';
}

final class VrRegionBudgetExceeded implements Exception {
  const VrRegionBudgetExceeded(this.key, this.sizeBytes);

  final VrRegionKey key;
  final int sizeBytes;

  @override
  String toString() => 'Region $key ($sizeBytes bytes) exceeds cache capacity.';
}

/// The persistence/transport hook. A host can first consult a bounded disk byte
/// store using key.cacheKey, then fetch and decode a missing region. The core
/// cache itself is memory-only and never downloads or writes data implicitly.
typedef VrRegionProvider<T> =
    Future<VrRegionData<T>> Function(
      VrRegionKey key,
      VrRegionCancellation cancellation,
    );

final class VrRegionSnapshot<T> {
  VrRegionSnapshot._({
    required this.current,
    required Map<VrRegionKey, VrRegionData<T>> resident,
    required Set<VrRegionKey> demanded,
    required this.residentBytes,
    required this.inFlightLoads,
    required Map<VrRegionKey, Object> errors,
  }) : resident = Map.unmodifiable(resident),
       demanded = Set.unmodifiable(demanded),
       errors = Map.unmodifiable(errors);

  final VrRegionKey? current;
  final Map<VrRegionKey, VrRegionData<T>> resident;
  final Set<VrRegionKey> demanded;
  final int residentBytes;
  final int inFlightLoads;
  final Map<VrRegionKey, Object> errors;

  VrRegionData<T>? get currentData => resident[current];
}

final class _Resident<T> {
  _Resident(this.data, this.lastAccess, this.accessOrder);
  final VrRegionData<T> data;
  DateTime lastAccess;
  int accessOrder;
}

/// Bounded region demand and memory caching, independent of visibility.
///
/// Only the neighborhood around the observer is enumerated: no world catalog
/// scan is needed. [prefetchRadiusCells] requests a square neighborhood, while
/// previously demanded cells remain wanted through [retentionRadiusCells] to
/// prevent boundary oscillation. Idle regions are evicted by TTL, then by LRU
/// under pressure; demanded regions prefer the nearest cells and the current
/// cell is protected. Oversized current regions fail explicitly, not unboundedly.
///
/// A request is attempted once per continuous demand. Call [retryFailures] for
/// an explicit retry. Repeated per-frame updates do not repeatedly fetch a failed
/// or rejected region. Use [prune] periodically to expire idle data when stopped.
/// Providers remain responsible for bounded downloads/decoding; the byte budget
/// is an admission limit and cannot limit allocations inside provider code.
final class VrRegionCache<T> {
  VrRegionCache({
    required this.grid,
    required this.provider,
    this.maxEntries = 32,
    this.maxBytes = 32 * 1024 * 1024,
    this.prefetchRadiusCells = 1,
    this.retentionRadiusCells = 2,
    this.maxConcurrentLoads = 2,
    this.idleTtl = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (maxEntries < 1 || maxEntries > 4096) {
      throw ArgumentError.value(maxEntries, 'maxEntries');
    }
    if (maxBytes < 1 || maxBytes > 2147483647) {
      throw ArgumentError.value(maxBytes, 'maxBytes');
    }
    if (prefetchRadiusCells < 0 || prefetchRadiusCells > 8) {
      throw ArgumentError.value(prefetchRadiusCells, 'prefetchRadiusCells');
    }
    if (retentionRadiusCells < prefetchRadiusCells ||
        retentionRadiusCells > 16) {
      throw ArgumentError.value(retentionRadiusCells, 'retentionRadiusCells');
    }
    if (maxConcurrentLoads < 1 || maxConcurrentLoads > 16) {
      throw ArgumentError.value(maxConcurrentLoads, 'maxConcurrentLoads');
    }
    if (idleTtl <= Duration.zero) {
      throw ArgumentError.value(idleTtl, 'idleTtl');
    }
  }

  final VrRegionGrid grid;
  final VrRegionProvider<T> provider;
  final int maxEntries;
  final int maxBytes;
  final int prefetchRadiusCells;
  final int retentionRadiusCells;
  final int maxConcurrentLoads;
  final Duration idleTtl;
  final DateTime Function() _clock;
  final _entries = <VrRegionKey, _Resident<T>>{};
  final _inFlight = <VrRegionKey, VrRegionCancellation>{};
  final _attempted = <VrRegionKey>{};
  final _errors = <VrRegionKey, Object>{};
  final _pending = <VrRegionKey>[];
  final _changes = StreamController<VrRegionSnapshot<T>>.broadcast();
  Set<VrRegionKey> _demanded = {};
  VrRegionKey? _current;
  Completer<void>? _idle;
  int _residentBytes = 0;
  int _accessOrder = 0;
  bool _disposed = false;

  Stream<VrRegionSnapshot<T>> get changes => _changes.stream;
  bool get isDisposed => _disposed;
  VrRegionSnapshot<T> get snapshot => VrRegionSnapshot._(
    current: _current,
    resident: _entries.map((key, entry) => MapEntry(key, entry.data)),
    demanded: _demanded,
    residentBytes: _residentBytes,
    inFlightLoads: _inFlight.length,
    errors: _errors,
  );

  VrRegionData<T>? peek(VrRegionKey key) => _entries[key]?.data;

  /// Marks a resident region used without fetching a missing one.
  VrRegionData<T>? read(VrRegionKey key) {
    _checkOpen();
    final entry = _entries[key];
    if (entry != null) _touch(entry);
    return entry?.data;
  }

  void updatePosition(VrWorldPosition position) {
    _checkOpen();
    final current = grid.keyAt(position);
    if (current == _current) {
      final active = _entries[current];
      if (active != null) _touch(active);
      return;
    }
    _current = current;
    final wanted = <VrRegionKey>{};
    for (var dx = -prefetchRadiusCells; dx <= prefetchRadiusCells; dx++) {
      for (var dz = -prefetchRadiusCells; dz <= prefetchRadiusCells; dz++) {
        wanted.add(grid.key(current.x + dx, current.z + dz));
      }
    }
    wanted.addAll(
      _demanded.where((key) => _cellDistance(key) <= retentionRadiusCells),
    );
    _demanded = wanted;
    _attempted.retainWhere(wanted.contains);
    _errors.removeWhere((key, _) => !wanted.contains(key));
    for (final MapEntry(:key, :value) in _inFlight.entries) {
      if (!wanted.contains(key)) value._isCancelled = true;
    }
    // A previously budget-rejected prefetch cell has become the active cell.
    if (!_entries.containsKey(current) &&
        !(_inFlight[current]?.isCancelled == false)) {
      _attempted.remove(current);
      _errors.remove(current);
    }
    for (final key in wanted) {
      final entry = _entries[key];
      if (entry != null) _touch(entry);
    }
    _pruneExpired();
    _rebuildPending();
    _pump();
    _emit();
  }

  /// Retry only the current bounded demand, including budget-rejected cells.
  void retryFailures() {
    _checkOpen();
    _attempted.removeWhere(
      (key) => !_entries.containsKey(key) && !_inFlight.containsKey(key),
    );
    _errors.clear();
    _rebuildPending();
    _pump();
    _emit();
  }

  void prune() {
    _checkOpen();
    _pruneExpired();
    _emit();
  }

  /// Resolves when currently queued and running provider calls have completed.
  /// A provider ignoring cancellation must still eventually finish. [dispose]
  /// releases this wait immediately without waiting for ignored cancellation.
  Future<void> waitForIdle() {
    if (_disposed || (_pending.isEmpty && _inFlight.isEmpty)) {
      return Future.value();
    }
    return (_idle ??= Completer<void>()).future;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final token in _inFlight.values) {
      token._isCancelled = true;
    }
    _inFlight.clear();
    _entries.clear();
    _pending.clear();
    _demanded.clear();
    _attempted.clear();
    _errors.clear();
    _residentBytes = 0;
    _current = null;
    _finishIdle();
    unawaited(_changes.close());
  }

  void _checkOpen() {
    if (_disposed) throw StateError('Region cache is disposed.');
  }

  int _cellDistance(VrRegionKey key) =>
      math.max((key.x - _current!.x).abs(), (key.z - _current!.z).abs());

  int _distanceSquared(VrRegionKey key) {
    final dx = key.x - _current!.x;
    final dz = key.z - _current!.z;
    return dx * dx + dz * dz;
  }

  void _touch(_Resident<T> entry) {
    entry.lastAccess = _clock();
    entry.accessOrder = ++_accessOrder;
  }

  void _pruneExpired() {
    final now = _clock();
    final expired = _entries.entries
        .where((entry) {
          return entry.key != _current &&
              !_demanded.contains(entry.key) &&
              now.difference(entry.value.lastAccess) >= idleTtl;
        })
        .map((entry) => entry.key)
        .toList();
    for (final key in expired) {
      _remove(key);
    }
  }

  void _remove(VrRegionKey key) {
    final previous = _entries.remove(key);
    if (previous != null) _residentBytes -= previous.data.sizeBytes;
  }

  void _rebuildPending() {
    _pending
      ..clear()
      ..addAll(
        _demanded.where(
          (key) => !_entries.containsKey(key) && !_attempted.contains(key),
        ),
      )
      ..sort((a, b) {
        final distance = _distanceSquared(a).compareTo(_distanceSquared(b));
        if (distance != 0) return distance;
        final x = a.x.compareTo(b.x);
        return x != 0 ? x : a.z.compareTo(b.z);
      });
  }

  void _pump() {
    if (_disposed) return;
    while (_inFlight.length < maxConcurrentLoads) {
      final index = _pending.indexWhere((key) => !_inFlight.containsKey(key));
      if (index == -1) break;
      final key = _pending.removeAt(index);
      if (_entries.containsKey(key) || !_demanded.contains(key)) continue;
      _attempted.add(key);
      final cancellation = VrRegionCancellation();
      _inFlight[key] = cancellation;
      unawaited(_fetch(key, cancellation));
    }
    if (_pending.isEmpty && _inFlight.isEmpty) _finishIdle();
  }

  Future<void> _fetch(
    VrRegionKey key,
    VrRegionCancellation cancellation,
  ) async {
    try {
      final data = await Future<VrRegionData<T>>.sync(
        () => provider(key, cancellation),
      );
      if (!_disposed && !cancellation.isCancelled && _demanded.contains(key)) {
        _admit(key, data);
      }
    } catch (error) {
      if (!_disposed && !cancellation.isCancelled && _demanded.contains(key)) {
        _errors[key] = error;
      }
    } finally {
      if (identical(_inFlight[key], cancellation)) _inFlight.remove(key);
      if (!_disposed) {
        _pump();
        _emit();
      }
    }
  }

  void _admit(VrRegionKey key, VrRegionData<T> data) {
    if (data.sizeBytes > maxBytes) {
      _errors[key] = VrRegionBudgetExceeded(key, data.sizeBytes);
      return;
    }
    final victims = <VrRegionKey>[];
    var remainingCount = _entries.length;
    var remainingBytes = _residentBytes;
    final candidates = _entries.keys.where((key) => key != _current).toList()
      ..sort((a, b) {
        final aWanted = _demanded.contains(a);
        final bWanted = _demanded.contains(b);
        if (aWanted != bWanted) return aWanted ? 1 : -1;
        if (aWanted) {
          final distance = _distanceSquared(b).compareTo(_distanceSquared(a));
          if (distance != 0) return distance;
        }
        return _entries[a]!.accessOrder.compareTo(_entries[b]!.accessOrder);
      });
    while (remainingCount >= maxEntries ||
        remainingBytes + data.sizeBytes > maxBytes) {
      if (victims.length >= candidates.length) return;
      final victim = candidates[victims.length];
      if (key != _current &&
          _demanded.contains(victim) &&
          _distanceSquared(victim) < _distanceSquared(key)) {
        return;
      }
      victims.add(victim);
      remainingCount--;
      remainingBytes -= _entries[victim]!.data.sizeBytes;
    }
    for (final victim in victims) {
      _remove(victim);
    }
    _entries[key] = _Resident(data, _clock(), ++_accessOrder);
    _residentBytes += data.sizeBytes;
    _errors.remove(key);
  }

  void _finishIdle() {
    final idle = _idle;
    _idle = null;
    if (idle != null && !idle.isCompleted) idle.complete();
  }

  void _emit() {
    if (!_disposed && _changes.hasListener) _changes.add(snapshot);
  }
}
