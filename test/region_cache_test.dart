import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:vrlizate_world/vrlizate_world.dart';

final world = VrWorldAddress(worldId: 'earth', instanceId: 'public');
VrRegionGrid grid({String id = 'cdmx-origin1-content1'}) =>
    VrRegionGrid(world: world, gridId: id, cellSizeMeters: 10);
VrWorldPosition position(int cell) => VrWorldPosition(cell * 10 + 1, 0, 1);
VrRegionData<String> data(VrRegionKey key, [int bytes = 10]) =>
    VrRegionData(value: key.cacheKey, sizeBytes: bytes);

void main() {
  test(
    'negative coordinates, height independence and stable key namespaces',
    () {
      final a = grid();
      expect(a.keyAt(VrWorldPosition(-0.1, 100, -10.1)), a.key(-1, -2));
      expect(a.keyAt(VrWorldPosition(1, -100, 1)), a.key(0, 0));
      expect(jsonDecode(a.key(3, -4).cacheKey), [
        'earth',
        'public',
        'cdmx-origin1-content1',
        3,
        -4,
      ]);
      expect(a.key(0, 0), isNot(grid(id: 'cdmx-origin2-content1').key(0, 0)));
      expect(a.key(0, 0), isNot(grid(id: 'cdmx-origin1-content2').key(0, 0)));
      expect(
        a.key(0, 0),
        isNot(
          VrRegionGrid(
            world: VrWorldAddress(worldId: 'earth', instanceId: 'private'),
            gridId: a.gridId,
          ).key(0, 0),
        ),
      );
    },
  );

  test('validates finite geometry, budgets and bounded neighborhood', () {
    expect(
      () => VrRegionGrid(world: world, gridId: 'x', cellSizeMeters: 0),
      throwsArgumentError,
    );
    expect(
      () => VrRegionGrid(world: world, gridId: 'x', cellSizeMeters: double.nan),
      throwsArgumentError,
    );
    expect(() => grid(id: '../unsafe'), throwsArgumentError);
    expect(() => VrRegionData(value: 'x', sizeBytes: -1), throwsArgumentError);
    Future<VrRegionData<String>> provider(
      VrRegionKey k,
      VrRegionCancellation c,
    ) async => data(k);
    expect(
      () => VrRegionCache(grid: grid(), provider: provider, maxEntries: 0),
      throwsArgumentError,
    );
    expect(
      () => VrRegionCache(grid: grid(), provider: provider, maxBytes: 0),
      throwsArgumentError,
    );
    expect(
      () => VrRegionCache(
        grid: grid(),
        provider: provider,
        prefetchRadiusCells: 9,
      ),
      throwsArgumentError,
    );
    expect(
      () => VrRegionCache(
        grid: grid(),
        provider: provider,
        retentionRadiusCells: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => VrRegionCache(
        grid: grid(),
        provider: provider,
        maxConcurrentLoads: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => VrRegionCache(
        grid: grid(),
        provider: provider,
        idleTtl: Duration.zero,
      ),
      throwsArgumentError,
    );
  });

  test(
    'loads current first, bounds concurrency, coalesces per-frame updates',
    () async {
      final started = <VrRegionKey>[];
      final waiting = <VrRegionKey, Completer<VrRegionData<String>>>{};
      final cache = VrRegionCache<String>(
        grid: grid(),
        provider: (key, _) {
          started.add(key);
          return (waiting[key] = Completer()).future;
        },
        maxConcurrentLoads: 2,
      );
      addTearDown(cache.dispose);
      cache.updatePosition(position(0));
      for (var i = 0; i < 20; i++) {
        cache.updatePosition(VrWorldPosition(2, 5, 2));
      }
      expect(started.length, 2);
      expect(started.first, cache.grid.key(0, 0));
      expect(cache.snapshot.demanded.length, 9);
      expect(cache.snapshot.inFlightLoads, 2);
      for (var i = 0; i < 9; i++) {
        final key = started[i];
        waiting[key]!.complete(data(key));
        await Future<void>.delayed(Duration.zero);
        expect(cache.snapshot.inFlightLoads, lessThanOrEqualTo(2));
      }
      await cache.waitForIdle();
      expect(started.toSet().length, 9);
      expect(cache.snapshot.resident.length, 9);
      expect(cache.snapshot.residentBytes, 90);
    },
  );

  test(
    'same-cell movement touches access without loads or change events',
    () async {
      var calls = 0, clockCalls = 0;
      StateError? clockError;
      final now = DateTime.utc(2026);
      final cache = VrRegionCache<String>(
        grid: grid(),
        provider: (key, _) async {
          calls++;
          return data(key);
        },
        prefetchRadiusCells: 0,
        retentionRadiusCells: 0,
        clock: () {
          clockCalls++;
          if (clockError != null) throw clockError;
          return now;
        },
      );
      addTearDown(cache.dispose);
      var events = 0;
      final subscription = cache.changes.listen((_) => events++);
      addTearDown(subscription.cancel);
      cache.updatePosition(position(0));
      await cache.waitForIdle();
      await Future<void>.delayed(Duration.zero);
      final initialEvents = events;
      clockCalls = 0;
      final movements = [
        VrWorldPosition(1, -100, 1),
        VrWorldPosition(9.999, 100, 9.999),
        VrWorldPosition(0, 0, 0),
        VrWorldPosition(5, 2, 5),
      ];
      for (final movement in movements) {
        cache.updatePosition(movement);
      }
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(clockCalls, movements.length);
      expect(events, initialEvents);
      expect(cache.snapshot.current, cache.grid.key(0, 0));
      expect(cache.snapshot.demanded, {cache.grid.key(0, 0)});
      expect(cache.snapshot.residentBytes, 10);

      final failure = StateError('clock unavailable');
      clockError = failure;
      expect(
        () => cache.updatePosition(movements.first),
        throwsA(same(failure)),
      );
      clockError = null;
      cache.updatePosition(movements.last);
      expect(calls, 1);
      cache.dispose();
      final callsBeforeDisposedUpdate = clockCalls;
      expect(() => cache.updatePosition(movements.last), throwsStateError);
      expect(clockCalls, callsBeforeDisposedUpdate);
    },
  );

  test(
    'cache cell selection matches the grid at signed and fractional boundaries',
    () async {
      for (final size in [.1, .3, 10.0, 64.0, 10000000.0]) {
        final regionGrid = VrRegionGrid(
          world: world,
          gridId: 'boundary-$size',
          cellSizeMeters: size,
        );
        final requested = <VrRegionKey, int>{};
        final cache = VrRegionCache<String>(
          grid: regionGrid,
          provider: (key, _) async {
            requested.update(key, (n) => n + 1, ifAbsent: () => 1);
            return data(key);
          },
          prefetchRadiusCells: 0,
          retentionRadiusCells: 0,
          clock: () => DateTime.utc(2026),
        );
        addTearDown(cache.dispose);
        final points = [
          VrWorldPosition.zero,
          VrWorldPosition(-0.0, 1, -0.0),
          VrWorldPosition(-double.minPositive, 0, double.minPositive),
          for (final factor in [-1.0, -1 + 1e-12, -.25, .25, 1 - 1e-12, 1.0])
            VrWorldPosition(size * factor, 100, -size * factor),
          VrWorldPosition(-10000000, 0, 10000000),
          VrWorldPosition(10000000, 0, -10000000),
        ];
        final visited = <VrRegionKey>{};
        for (final point in points) {
          final expected = regionGrid.keyAt(point);
          visited.add(expected);
          for (var repeat = 0; repeat < 2; repeat++) {
            cache.updatePosition(point);
            await cache.waitForIdle();
            expect(cache.snapshot.current, expected);
            expect(cache.snapshot.demanded, {expected});
            expect(cache.snapshot.currentData, isNotNull);
            expect(cache.snapshot.errors, isEmpty);
          }
        }
        expect(requested.keys.toSet(), visited);
        expect(requested.values, everyElement(1));
      }
    },
  );

  test(
    'bounded demand at far coordinates never scans intervening cells',
    () async {
      var calls = 0;
      final cache = VrRegionCache<String>(
        grid: grid(),
        provider: (key, _) async {
          calls++;
          return data(key);
        },
      );
      addTearDown(cache.dispose);
      cache.updatePosition(VrWorldPosition(9999999, 0, -9999999));
      await cache.waitForIdle();
      expect(calls, 9);
      expect(cache.snapshot.demanded.length, 9);
    },
  );

  test('retention hysteresis reuses both sides of a boundary', () async {
    var calls = 0;
    final cache = VrRegionCache<String>(
      grid: grid(),
      provider: (key, _) async {
        calls++;
        return data(key);
      },
      prefetchRadiusCells: 0,
      retentionRadiusCells: 1,
    );
    addTearDown(cache.dispose);
    for (final cell in [0, 1, 0, 1, 0]) {
      cache.updatePosition(position(cell));
      await cache.waitForIdle();
    }
    expect(calls, 2);
    expect(cache.snapshot.demanded.length, 2);
    cache.updatePosition(position(10));
    await cache.waitForIdle();
    expect(cache.snapshot.demanded, {cache.grid.key(10, 0)});
  });

  test(
    'byte and entry admission limits preserve current over prefetch',
    () async {
      final cache = VrRegionCache<String>(
        grid: grid(),
        provider: (key, _) async =>
            data(key, key.x == 0 && key.z == 0 ? 70 : 20),
        maxBytes: 100,
        maxEntries: 2,
      );
      addTearDown(cache.dispose);
      cache.updatePosition(position(0));
      await cache.waitForIdle();
      expect(cache.snapshot.currentData!.sizeBytes, 70);
      expect(cache.snapshot.resident.length, 2);
      expect(cache.snapshot.residentBytes, 90);
      final other = cache.snapshot.resident.keys.firstWhere(
        (key) => key != cache.snapshot.current,
      );
      expect(
        other.x.abs() + other.z.abs(),
        1,
        reason: 'nearest neighbors have priority over diagonal prefetch',
      );
    },
  );

  test(
    'previously rejected prefetch becomes loadable when made current',
    () async {
      final loads = <VrRegionKey, int>{};
      final cache = VrRegionCache<String>(
        grid: grid(),
        provider: (key, _) async {
          loads.update(key, (n) => n + 1, ifAbsent: () => 1);
          return data(key);
        },
        maxEntries: 1,
      );
      addTearDown(cache.dispose);
      cache.updatePosition(position(0));
      await cache.waitForIdle();
      final next = cache.grid.key(1, 0);
      expect(cache.peek(next), isNull);
      expect(loads[next], 1);
      cache.updatePosition(position(1));
      await cache.waitForIdle();
      expect(cache.snapshot.currentData!.value, next.cacheKey);
      expect(loads[next], 2);
      expect(cache.snapshot.resident.length, 1);
    },
  );

  test(
    'TTL evicts departed cells, keeps demanded cells and redownloads later',
    () async {
      var time = DateTime.utc(2026);
      var calls = 0;
      final cache = VrRegionCache<String>(
        grid: grid(),
        provider: (key, _) async {
          calls++;
          return data(key);
        },
        prefetchRadiusCells: 0,
        retentionRadiusCells: 0,
        idleTtl: const Duration(seconds: 10),
        clock: () => time,
      );
      addTearDown(cache.dispose);
      cache.updatePosition(position(0));
      await cache.waitForIdle();
      cache.updatePosition(position(1));
      await cache.waitForIdle();
      time = time.add(const Duration(seconds: 9));
      cache.prune();
      expect(cache.snapshot.resident.length, 2);
      time = time.add(const Duration(seconds: 1));
      cache.prune();
      expect(cache.snapshot.resident.keys, [cache.grid.key(1, 0)]);
      cache.updatePosition(position(0));
      await cache.waitForIdle();
      expect(calls, 3);
      expect(cache.snapshot.currentData, isNotNull);
    },
  );

  test('same-cell movement refreshes TTL before leaving a region', () async {
    var time = DateTime.utc(2026);
    final cache = VrRegionCache<String>(
      grid: grid(),
      provider: (key, _) async => data(key),
      prefetchRadiusCells: 0,
      retentionRadiusCells: 0,
      idleTtl: const Duration(seconds: 10),
      clock: () => time,
    );
    addTearDown(cache.dispose);
    final origin = cache.grid.key(0, 0);
    cache.updatePosition(position(0));
    await cache.waitForIdle();
    time = time.add(const Duration(seconds: 8));
    cache.updatePosition(VrWorldPosition(9, 5, 9));
    time = time.add(const Duration(seconds: 1));
    cache.updatePosition(position(1));
    await cache.waitForIdle();
    time = time.add(const Duration(seconds: 3));
    cache.prune();
    expect(cache.peek(origin), isNotNull);
    time = time.add(const Duration(seconds: 6));
    cache.prune();
    expect(cache.peek(origin), isNull);
    expect(cache.snapshot.currentData, isNotNull);
  });

  test(
    'LRU evicts least recently used idle region and read refreshes access',
    () async {
      final cache = VrRegionCache<String>(
        grid: grid(),
        provider: (key, _) async => data(key),
        prefetchRadiusCells: 0,
        retentionRadiusCells: 0,
        maxEntries: 3,
      );
      addTearDown(cache.dispose);
      for (final cell in [0, 1, 2]) {
        cache.updatePosition(position(cell));
        await cache.waitForIdle();
      }
      cache.read(cache.grid.key(0, 0));
      cache.updatePosition(position(3));
      await cache.waitForIdle();
      expect(cache.peek(cache.grid.key(1, 0)), isNull);
      expect(cache.snapshot.resident.keys.toSet(), {
        cache.grid.key(0, 0),
        cache.grid.key(2, 0),
        cache.grid.key(3, 0),
      });
    },
  );

  test(
    'same-cell access retains LRU priority after leaving the cell',
    () async {
      final now = DateTime.utc(2026);
      final cache = VrRegionCache<String>(
        grid: grid(),
        provider: (key, _) async => data(key),
        prefetchRadiusCells: 0,
        retentionRadiusCells: 0,
        maxEntries: 3,
        clock: () => now,
      );
      addTearDown(cache.dispose);
      for (final cell in [0, 1, 2]) {
        cache.updatePosition(position(cell));
        await cache.waitForIdle();
      }
      cache.read(cache.grid.key(0, 0));
      cache.updatePosition(VrWorldPosition(29, 5, 9));
      for (final cell in [3, 4]) {
        cache.updatePosition(position(cell));
        await cache.waitForIdle();
      }
      expect(cache.snapshot.resident.keys.toSet(), {
        cache.grid.key(2, 0),
        cache.grid.key(3, 0),
        cache.grid.key(4, 0),
      });
    },
  );

  test('cached return does not refetch', () async {
    var calls = 0;
    final cache = VrRegionCache<String>(
      grid: grid(),
      provider: (key, _) async {
        calls++;
        return data(key);
      },
      prefetchRadiusCells: 0,
      retentionRadiusCells: 0,
    );
    addTearDown(cache.dispose);
    for (final cell in [0, 10, 0]) {
      cache.updatePosition(position(cell));
      await cache.waitForIdle();
    }
    expect(calls, 2);
  });

  test('ignored cancellation cannot resurrect a departed region', () async {
    final pending = <VrRegionKey, Completer<VrRegionData<String>>>{};
    final tokens = <VrRegionKey, VrRegionCancellation>{};
    final cache = VrRegionCache<String>(
      grid: grid(),
      provider: (key, token) {
        tokens[key] = token;
        return (pending[key] = Completer()).future;
      },
      prefetchRadiusCells: 0,
      retentionRadiusCells: 0,
    );
    addTearDown(cache.dispose);
    final old = cache.grid.key(0, 0);
    final current = cache.grid.key(10, 0);
    cache.updatePosition(position(0));
    cache.updatePosition(position(10));
    expect(tokens[old]!.isCancelled, isTrue);
    expect(
      tokens[old]!.throwIfCancelled,
      throwsA(isA<VrRegionLoadCancelled>()),
    );
    pending[current]!.complete(data(current));
    pending[old]!.complete(data(old));
    await cache.waitForIdle();
    expect(cache.snapshot.resident.keys, [current]);
  });

  test(
    'leave and return during canceled load starts a fresh request without duplicates',
    () async {
      final pending = <(VrRegionKey, int), Completer<VrRegionData<String>>>{};
      final counts = <VrRegionKey, int>{};
      final cache = VrRegionCache<String>(
        grid: grid(),
        provider: (key, token) {
          final count = counts.update(key, (n) => n + 1, ifAbsent: () => 1);
          return (pending[(key, count)] = Completer()).future;
        },
        prefetchRadiusCells: 0,
        retentionRadiusCells: 0,
        maxConcurrentLoads: 1,
      );
      addTearDown(cache.dispose);
      final key = cache.grid.key(0, 0);
      cache.updatePosition(position(0));
      cache.updatePosition(position(10));
      cache.updatePosition(position(0));
      pending[(key, 1)]!.complete(data(key));
      await Future<void>.delayed(Duration.zero);
      expect(cache.peek(key), isNull);
      expect(counts[key], 2);
      pending[(key, 2)]!.complete(data(key));
      await cache.waitForIdle();
      expect(cache.snapshot.currentData, isNotNull);
      expect(counts.length, 1);
    },
  );

  test(
    'provider errors do not escape or retry every frame; explicit retry succeeds',
    () async {
      var attempts = 0;
      final cache = VrRegionCache<String>(
        grid: grid(),
        provider: (key, _) {
          attempts++;
          if (attempts == 1) throw StateError('offline');
          return Future.value(data(key));
        },
        prefetchRadiusCells: 0,
      );
      addTearDown(cache.dispose);
      cache.updatePosition(position(0));
      await cache.waitForIdle();
      expect(cache.snapshot.errors.values.single, isStateError);
      for (var i = 0; i < 30; i++) {
        cache.updatePosition(position(0));
      }
      await cache.waitForIdle();
      expect(attempts, 1);
      cache.retryFailures();
      await cache.waitForIdle();
      expect(attempts, 2);
      expect(cache.snapshot.errors, isEmpty);
    },
  );

  test(
    'oversized active region reports budget error without exceeding budgets',
    () async {
      final cache = VrRegionCache<String>(
        grid: grid(),
        provider: (key, _) async => data(key, 101),
        prefetchRadiusCells: 0,
        maxBytes: 100,
      );
      addTearDown(cache.dispose);
      cache.updatePosition(position(0));
      await cache.waitForIdle();
      expect(cache.snapshot.currentData, isNull);
      expect(cache.snapshot.residentBytes, 0);
      expect(
        cache.snapshot.errors.values.single,
        isA<VrRegionBudgetExceeded>(),
      );
    },
  );

  test(
    'snapshot immutable; disposal cancels, releases wait, and discards late data',
    () async {
      final pending = Completer<VrRegionData<String>>();
      late VrRegionCancellation token;
      final cache = VrRegionCache<String>(
        grid: grid(),
        provider: (key, cancellation) {
          token = cancellation;
          return pending.future;
        },
        prefetchRadiusCells: 0,
      );
      cache.updatePosition(position(0));
      final snapshot = cache.snapshot;
      expect(() => snapshot.demanded.clear(), throwsUnsupportedError);
      expect(() => snapshot.resident.clear(), throwsUnsupportedError);
      final idle = cache.waitForIdle();
      cache.dispose();
      await idle;
      expect(token.isCancelled, isTrue);
      pending.complete(data(cache.grid.key(0, 0)));
      await Future<void>.delayed(Duration.zero);
      expect(cache.snapshot.resident, isEmpty);
      expect(cache.snapshot.inFlightLoads, 0);
      expect(() => cache.updatePosition(position(0)), throwsStateError);
      cache.dispose();
    },
  );

  test(
    'long travel keeps resident, demand and error metadata bounded',
    () async {
      final cache = VrRegionCache<String>(
        grid: grid(),
        provider: (key, _) async {
          if (key.x.isOdd) throw StateError('offline');
          return data(key);
        },
        maxEntries: 5,
        maxBytes: 50,
      );
      addTearDown(cache.dispose);
      for (var cell = 0; cell < 100; cell++) {
        cache.updatePosition(position(cell));
        await cache.waitForIdle();
        expect(cache.snapshot.resident.length, lessThanOrEqualTo(5));
        expect(cache.snapshot.residentBytes, lessThanOrEqualTo(50));
        expect(cache.snapshot.demanded.length, lessThanOrEqualTo(25));
        expect(cache.snapshot.errors.length, lessThanOrEqualTo(25));
      }
    },
  );
}
