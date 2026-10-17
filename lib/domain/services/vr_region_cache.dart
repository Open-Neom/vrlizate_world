import 'dart:async';
import 'dart:math' as math;

import '../../utils/constants/vr_world_constants.dart';
import '../models/vr_region_budget_exceeded.dart';
import '../models/vr_region_cancellation.dart';
import '../models/vr_region_data.dart';
import '../models/vr_region_grid.dart';
import '../models/vr_region_key.dart';
import '../models/vr_region_snapshot.dart';
import '../models/vr_world_position.dart';

/// The persistence/transport hook. A host can first consult a bounded disk byte
/// store using key.cacheKey, then fetch and decode a missing region. The core
/// cache itself is memory-only and never downloads or writes data implicitly.
typedef VrRegionProvider<T> =
    Future<VrRegionData<T>> Function(
      VrRegionKey key,
      VrRegionCancellation cancellation,
    );

typedef _ResidentRecord<T> = ({
  VrRegionData<T> data,
  DateTime lastAccess,
  int accessOrder,
});

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
    this.maxEntries = VrWorldConstants.defaultRegionCacheMaxEntries,
    this.maxBytes = VrWorldConstants.defaultRegionCacheMaxBytes,
    this.prefetchRadiusCells = VrWorldConstants.defaultPrefetchRadiusCells,
    this.retentionRadiusCells = VrWorldConstants.defaultRetentionRadiusCells,
    this.maxConcurrentLoads = VrWorldConstants.defaultMaxConcurrentLoads,
    this.idleTtl = const Duration(
      minutes: VrWorldConstants.defaultIdleTtlMinutes,
    ),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (maxEntries < 1 ||
        maxEntries > VrWorldConstants.maxRegionCacheEntriesLimit) {
      throw ArgumentError.value(maxEntries, VrWorldConstants.paramMaxEntries);
    }
    if (maxBytes < 1 || maxBytes > VrWorldConstants.maxRegionDataBytes) {
      throw ArgumentError.value(maxBytes, VrWorldConstants.paramMaxBytes);
    }
    if (prefetchRadiusCells < 0 ||
        prefetchRadiusCells > VrWorldConstants.maxPrefetchRadiusCells) {
      throw ArgumentError.value(
        prefetchRadiusCells,
        VrWorldConstants.paramPrefetchRadiusCells,
      );
    }
    if (retentionRadiusCells < prefetchRadiusCells ||
        retentionRadiusCells > VrWorldConstants.maxRetentionRadiusCells) {
      throw ArgumentError.value(
        retentionRadiusCells,
        VrWorldConstants.paramRetentionRadiusCells,
      );
    }
    if (maxConcurrentLoads < 1 ||
        maxConcurrentLoads > VrWorldConstants.maxConcurrentLoadsLimit) {
      throw ArgumentError.value(
        maxConcurrentLoads,
        VrWorldConstants.paramMaxConcurrentLoads,
      );
    }
    if (idleTtl <= Duration.zero) {
      throw ArgumentError.value(idleTtl, VrWorldConstants.paramIdleTtl);
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
  final _entries = <VrRegionKey, _ResidentRecord<T>>{};
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
  VrRegionSnapshot<T> get snapshot => VrRegionSnapshot(
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
    if (entry != null) _touch(key, entry);
    return entry?.data;
  }

  void updatePosition(VrWorldPosition position) {
    _checkOpen();
    final current = grid.keyAt(position);
    if (current == _current) {
      final active = _entries[current];
      if (active != null) _touch(current, active);
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
      if (!wanted.contains(key)) value.cancel();
    }
    // A previously budget-rejected prefetch cell has become the active cell.
    if (!_entries.containsKey(current) &&
        !(_inFlight[current]?.isCancelled == false)) {
      _attempted.remove(current);
      _errors.remove(current);
    }
    for (final key in wanted) {
      final entry = _entries[key];
      if (entry != null) _touch(key, entry);
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
      token.cancel();
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
    if (_disposed) throw StateError(VrWorldConstants.errRegionCacheDisposed);
  }

  int _cellDistance(VrRegionKey key) =>
      math.max((key.x - _current!.x).abs(), (key.z - _current!.z).abs());

  int _distanceSquared(VrRegionKey key) {
    final dx = key.x - _current!.x;
    final dz = key.z - _current!.z;
    return dx * dx + dz * dz;
  }

  void _touch(VrRegionKey key, _ResidentRecord<T> entry) {
    _entries[key] = (
      data: entry.data,
      lastAccess: _clock(),
      accessOrder: ++_accessOrder,
    );
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
    _entries[key] = (
      data: data,
      lastAccess: _clock(),
      accessOrder: ++_accessOrder,
    );
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
