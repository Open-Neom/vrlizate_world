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
- **Paquetes de lugares `.vrlw` (`VrlwBundleCodec`, `VrlwPlaceReader`, `VrlwRegionProvider`):** contenedor `VRLW0001` con índice frontal, regiones comprimidas independientes (`DEFLATE`/`STORE`), recursos estáticos de modelo/textura/audio opcionales, contratos declarativos acotados de movimiento/interacción y decodificación de bloques grandes en isolate nativo con fallback inline en web.

## Mundos con movimiento, controles y sonido

La beta **VRLW v1** incorpora `VrlwMotionSpec` y `VrlwInteractionSpec` en
`VrlwBundleIndex.motions`/`interactions`, con un máximo de ocho entradas de cada
tipo. El codec puro Dart valida referencias, coordenadas, periodos y amplitudes;
no ejecuta animaciones, reproduce audio ni crea recursos de GPU. Los campos
opcionales vacíos se omiten, manteniendo los bytes de los documentos anteriores.
Un lector beta que no conozca los campos nuevos los rechaza.

El host móvil actualizado de `vrlizate_apps` admite giro `spin`, oscilación `bob`
y recorridos cerrados `path` de un nodo
GLB con nombre único, malla y transformación implícita identidad, sin hijos y
directamente en la escena activa. Aplica un máximo de 16 instancias de primitivas
móviles residentes y actualiza las transformaciones hasta 30 Hz; no promete una
tasa de renderizado. Los controles cercanos solo permiten `toggleMotion` o
`toggleAudio`, con alcance máximo de cuatro metros y cooldown de 0,4 segundos.
Los toggles y la fase se retienen al recorrer portales dentro de esa instancia
del visor; no se guardan en el archivo, en el snapshot persistente ni en red.

El codec general conserva sus tipos de recursos `audio.*`, mientras que el
perfil móvil de Apps restringe cada mundo a ocho recursos no sonoros más un
único WAV PCM canónico: mono, 16 bits, 16 000 o 22 050 Hz, hasta 256 KiB y ocho
segundos. La salida de audio se inyecta de forma optativa por el host, que
mantiene como máximo dos voces y actualizaciones a 10 Hz. VRlizate reutiliza
`neom_sound`/SoLoud mediante su adaptador; World no añade dependencias nativas.

`path` declara 3–16 waypoints modelo-locales dentro de ±32 m y un periodo de
2–120 s, con fase inicial y orientación opcionales. El objeto inmutable
`VrlwDayNightCycleSpec`, en `environment.dayNightCycle`, añade un día visual de
120–7 200 s y hora inicial de 0 a menos de 24. Ambas capacidades conservan v1 beta
sin ejecutar código descargado; su admisión exige un consumidor actualizado.

Consulta los [campos y límites del formato](doc/vrlw_format.md#movimiento-e-interacciones-declarativos),
el [perfil móvil de Apps](../vrlizate_apps/doc/vrlz_format.md#movimiento-controles-y-audio-de-mundos-v1-beta)
y la [guía de autoría de la biblioteca](https://github.com/Open-Neom/codebase_vrlw/blob/main/docs/LIVING_WORLDS_MOBILE.md).

## Herramientas CLI

```sh
dart run tool/pack_vrlw.dart tool/fixtures/forest.vrlw.json build/forest.vrlw
dart run tool/read_vrlw.dart build/forest.vrlw
dart run tool/benchmark_vrlw.dart
```

## Verificación

```sh
dart analyze lib test tool
dart test
```

El lote de contratos de la ampliación del 25 de octubre de 2026 pasó 84 pruebas:
`vrlw_behaviors_test.dart` (47 casos nuevos), `vrlw_resources_test.dart` y
`vrlw_bundle_test.dart`. Comprueba paridad de compilador/lector estricto,
referencias, límites, números inválidos, copias inmutables y compatibilidad de
bytes. La presentación, el audio nativo y el rendimiento se verifican en sus
consumidores; este resultado no mide FPS ni valida una GPU de teléfono.

## Licencia

Apache License 2.0 — consulta [LICENSE](LICENSE).
