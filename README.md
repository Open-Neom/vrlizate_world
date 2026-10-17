# vrlizate_world

Coordenadas locales neutrales al renderizador, registro espacial de entidades, portales inter-mundo, paquetes de lugares `.vrlw` indexados y caché de regiones para el **VRlizate SDK**. Puro Dart (sin dependencias de Flutter, Firebase ni red).

> Versión actual: **1.0.0**. Consulta [CHANGELOG.md](CHANGELOG.md), la [guía `.vrlw`](doc/vrlw_guide.md) y la [especificación `.vrlw` v1 beta](doc/vrlw_format.md).

## Ejemplo rápido

```dart
import 'package:vrlizate_world/vrlizate_world.dart';

final plaza = VrWorldAddress(worldId: 'vrlizate.plaza', instanceId: 'local');
final builder = VrWorldBuilder(
  world: plaza,
  environmentPreset: VrWorldEnvironmentPreset.cyberpunkNeon,
)
  ..placeEntity(
    id: 'plaza-tree-1',
    prototypeId: 'tree.plaza',
    position: VrWorldPosition(-6, 0, 24),
  )
  ..linkPortal(
    id: 'portal-arena',
    targetWorld: VrWorldAddress(worldId: 'vrlizate.arena'),
    localPosition: VrWorldPosition(0, 0, 12),
    triggerRadiusMeters: 2.0,
    label: 'Cyber Arena',
  );

final world = builder.buildRegistry();
final nearby = world.queryRadius(
  center: VrWorldPosition(0, 1.6, 22),
  radiusMeters: 15,
);
```

## Componentes principales

- **`VrWorldAddress`, `VrWorldPosition`, `VrWorldEntity` y `VrWorldRegistry`:** coordenadas en metros (`+X` derecha, `+Y` arriba, `-Z` frente, límite `±10^7` m), indexación en cuadrícula X/Z y consultas espaciales por radio (hasta 100,000 entidades).
- **`VrWorldEnvironmentPreset`, `VrPortalLink` y `VrWorldBuilder`:** presets de iluminación ambiental/cielo/niebla, enlaces de portal inter-mundo con radio de activación y constructor fluido de mundos.
- **Streaming y caché de regiones (`VrRegionGrid`, `VrRegionCache<T>`):** precarga de celdas vecinas con concurrencia acotada, histéresis de retención, presupuestos de bytes/entradas y política TTL/LRU.
- **Caché persistente en disco (`package:vrlizate_world/vrlizate_world_io.dart`):** `VrRegionDiskCache` con escrituras atómicas, poda por edad/tamaño y verificación contra corrupción.
- **Paquetes de lugares `.vrlw` (`VrlwBundleCodec`, `VrlwPlaceReader`, `VrlwRegionProvider`):** contenedor `VRLW0001` con índice frontal, regiones comprimidas independientes (`DEFLATE`/`STORE`), recursos estáticos GLB/RGBA8 opcionales y decodificación de bloques grandes en isolate nativo con fallback inline en web.

## Herramientas CLI

```sh
dart run tool/pack_vrlw.dart tool/fixtures/forest.vrlw.json build/forest.vrlw
dart run tool/read_vrlw.dart build/forest.vrlw
dart run tool/benchmark_vrlw.dart
```

## Verificación

```sh
flutter analyze
flutter test
```

## Licencia

Apache License 2.0 — consulta [LICENSE](LICENSE).
