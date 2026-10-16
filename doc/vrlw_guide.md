# Crear y compartir lugares `.vrlw`

Guía para autores e implementadores. Actualizada el 10 de octubre de 2026 para
VRLW v1 beta y el código de VRlizate SDK preview.7. Es un formato experimental:
la especificación y los ejemplos están en este repositorio local; esta guía
no implica que se haya publicado una descarga, un estándar o un paquete en Pub.

## Qué representa un archivo

Un `.vrlw` describe un lugar dividido en regiones: dónde aparece cada objeto,
qué prototipo utiliza y cómo se orienta/escala. La plataforma puede leer regiones
cercanas, conservarlas en caché y dejar de dibujarlas cuando ya no son necesarias.

| Elemento | Papel |
| --- | --- |
| `.vrlz` | Experiencia compatible con alguno de los runtimes de la plataforma. |
| `.vrlw` v1 beta | Entidades, prototipos y recursos GLB/RGBA8 opcionales con vinculaciones validadas. |
| `vrlizate_world` | Compilación, validación, coordenadas, lector y caché de regiones. |
| `vrlizate_apps` | Transporte HTTPS por rangos para lugares y APIs de experiencias. |
| Host/renderizador | Permisos, prototipos, geometría, materiales, física, audio y presentación. |

Esta versión no contiene Dart ejecutable ni audio propio. La base permite
referenciar prototipos del host: declarar `openworld.tree` no descarga un árbol.
La ampliación de esta misma beta también admite GLB estático y texturas RGBA8
con vinculaciones explícitas, validadas por el host. Consultar la
[autoría externa y mundos conectados](../../docs/creator_worlds_beta.md) para ese
perfil y la [hoja de ruta de v1 beta](vrlw_beta_roadmap.md) para lo pendiente.

La [especificación binaria](vrlw_format.md) contiene los límites y reglas exactos.
La [nota de nombres](vrlw_naming.md) explica por qué se conservan cuatro letras.

## Primer lugar, sin Flutter ni GPU

Usar Dart compatible con `pubspec.yaml` (actualmente `^3.10.8`). Desde la carpeta
`vrlizate_world` del SDK:

```sh
dart pub get
dart run tool/pack_vrlw.dart doc/examples/garden.vrlw.json /tmp/garden-demo.vrlw
dart run doc/examples/read_garden.dart /tmp/garden-demo.vrlw
```

`/tmp` es una ruta de ejemplo para macOS/Linux; en Windows elegir otra carpeta
escribible. El empaquetador no sobrescribe salidas: cambiar el nombre al repetir
la prueba. En un proyecto externo, añadir `vrlizate_world` como dependencia `path`
al SDK descargado/extraído; el módulo todavía tiene `publish_to: none`.

La [fuente editable](examples/garden.vrlw.json) define un árbol en `(2, 0, 3)`
metros, con escala `1.5`, dentro de la región `(0, 0)` de 12 metros. El
[lector ejecutable](examples/read_garden.dart) imprime sus datos, verifica límites
y cierra la caché/fuente al terminar. No abre una ventana 3D.

El compilador imprime el SHA-256 del índice. Para comprobar una copia distribuida,
pasar ese valor como segundo argumento al lector:

```sh
dart run doc/examples/read_garden.dart /tmp/garden-demo.vrlw SHA256_DEL_INDICE_CONFIABLE
```

El hash debe proceder del artefacto aprobado o de un catálogo confiable. Leer el
hash del mismo archivo recibido solo identifica el contenido; no autentica al
autor. La licencia de este ejemplo es Apache-2.0, como el módulo. Para un lugar
propio se debe declarar la licencia correspondiente y conservar los avisos de
sus componentes al distribuirlos.

## Autoría: reglas para evitar incompatibilidades

El JSON fuente y el binario compilado son archivos distintos. La fuente lleva
`regions`; el compilador produce un índice `chunks`, calcula offsets/hashes y
comprime cada región independientemente. Renombrar un JSON a `.vrlw` no lo convierte.

| Campo o dato | Regla v1 |
| --- | --- |
| `schemaVersion` | Entero `1`; campos desconocidos se rechazan. |
| `id`, `revision`, `gridId`, IDs de entidad/prototipo | De 1 a 128 caracteres ASCII; empezar por letra/dígito; luego letras, dígitos, `.`, `_`, `:`, `-`. |
| `title` / `license` | Texto no vacío sin controles ASCII (`U+0000`–`U+001F`, `U+007F`); máximos 160 / 2,048 unidades UTF-16 según `String.length` de Dart. |
| `cellSizeMeters` | Número finito entre `0.1` y `10,000,000`; elegir celdas pequeñas y densidad medible. |
| Región `(x, z)` | Índices enteros; toda la celda debe quedar dentro del marco local admitido. |
| Entidad `(x, y, z)` | X/Z locales a la región: `0 <= valor < cellSizeMeters`; Y es altura en el marco del lugar. |
| `yawRadians` | Opcional, cero por defecto; número finito entre −1e9 y 1e9, normalizado por el modelo de transformación. |
| `scale` | Opcional, uno por defecto; uniforme, positiva y no mayor de 1,000. |
| `prototypes` | Lista sin repetidos, hasta 1,024 IDs. Cada referencia debe estar declarada y admitida por el host. |
| `origin` | Local por defecto; `wgs84-enu` es metadata que requiere una transformación explícita del host. |

Ejemplo de coordenadas: celda `(-1, 0)` de 12 metros + entidad local `(2, 0, 3)`
produce posición mundial `(-10, 0, 3)`. No insertar `-10` en la X local de esa
entidad. Los ejes locales son +X derecha, +Y arriba y −Z adelante.

Cambiar el origen, tamaño de celda o contenido exige revisar la identidad de
autoría. El proveedor aísla la caché usando el hash exacto del índice. La instancia
la asigna el host; escribir un ID no concede acceso a una sesión privada.

## Integración con una experiencia

El lector de ejemplo demuestra la secuencia mínima:

1. Abrir la fuente; el índice se valida antes de solicitar regiones.
2. Declarar los prototipos que el host realmente puede materializar.
3. Crear `VrlwRegionProvider` y `VrRegionCache` con presupuestos adecuados.
4. Actualizar la posición del observador y consumir los datos residentes.
5. Incorporar las entidades a un registro acotado, rechazando IDs repetidos.
6. Dibujar con geometría/materiales compartidos, LOD y descarte por visibilidad.
7. Al suspender/salir, cancelar cargas y liberar recursos; guardar el estado del
   usuario fuera de las cachés descartables.

El perfil `.vrlz` `vrlizate.worlds.v1` ya declara lugares empaquetados y portales
locales entre ellos, con aliases, hashes y puntos de llegada validados. Los
contratos de dependencias remotas, montajes aditivos y permisos entre experiencias
siguen pendientes: `worlds.local` no concede acceso libre a la red. El host también
puede conectar escenas conocidas con su navegación propia sin declarar esos
vínculos en un archivo.

La biblioteca de Home no descubre `.vrlw` arbitrarios por extensión. El
[piloto de ambientes conectados](../../../../VRlizate_app/docs/CONNECTED_WORLDS_BETA.md)
de OpenWorld usa lugares empaquetados de bosque, desierto y tundra, con portales
y materiales registrados en el host. Puerto Neom sigue siendo una escena del
host. La comprobación estéreo anterior del bosque en el S25 no valida los nuevos
ambientes ni acredita un aumento cuantificado de FPS.

## Distribuir mediante hosting

El archivo puede alojarse como bytes estáticos en una URL HTTPS final. Para el
lector por rangos, el servidor debe responder `206`, `Content-Range` coherente,
ETag fuerte estable y bytes sin compresión HTTP adicional. Cada solicitud debe
referirse a la misma revisión; publicar nuevas revisiones con otra URL simplifica
ese control. No basta con que la URL permita descargar el archivo completo.

El host utiliza `VrlwHttpSource` de `vrlizate_apps` en lugar de `VrlwFileSource`,
manteniendo el lector/proveedor. Consultar las condiciones de CORS y transporte
en la [especificación](vrlw_format.md#fuentes-locales-y-https).

No hay un tipo MIME específico registrado por este SDK. Para distribución binaria
general se puede servir `application/octet-stream`. Ni MIME ni extensión sustituyen
la comprobación de cabecera, versión, integridad y límites. El catálogo confiable,
no un campo escrito por el autor, decide qué contenido se puede abrir.

## Calidad y consumo

El peso comprimido no representa la memoria ni el tiempo de un frame. V1 limita
cada bloque expandido a 2 MiB y 4,096 entidades, pero esos máximos no son objetivos
de densidad. Preferir regiones suficientemente pequeñas, prototipos reutilizados
y pruebas sobre el teléfono menos potente que se quiera admitir.

El proveedor decodifica bloques de al menos 64 KiB expandidos en un isolate nativo;
web conserva la ruta inline. El límite de cargas concurrentes y las subidas GPU
pertenecen al host. Caché en disco, datos CPU y recursos GPU son presupuestos distintos.

Se incluyen herramientas para separar esos costes:

```sh
dart run tool/read_vrlw.dart tool/fixtures/forest.vrlw 1 1
dart run tool/benchmark_vrlw.dart --samples 200 --warmup 20
```

El benchmark mide CPU del códec, no FPS. En la app, medir en modo profile y usar
el protocolo `VRlizate_app/docs/OPENWORLD_PERFORMANCE.md` cuando el repositorio de
la app esté disponible en el workspace. La app no forma parte del ZIP mínimo
del SDK.

## Errores frecuentes

| Síntoma | Comprobación |
| --- | --- |
| Magic/version no admitido | Confirmar que se compiló JSON; no basta renombrar otro archivo. |
| Prototipo ausente | Registrar una implementación compatible en el host; no desactivar la validación. |
| Coordenada fuera de región | Revisar X/Z locales y bordes superiores exclusivos. |
| Hash distinto | Comparar el índice esperado de la revisión aprobada; no sustituirlo automáticamente por el recibido. |
| HTTP devuelve 200 o ETag débil | Configurar el hosting para rangos/versionado o usar una copia local validada. |
| Tirón al cargar | Separar decode, creación GPU y simulación; bajar densidad/LOD y medir cada etapa. |
| Archivo válido pero sin escena | El paquete describe datos; el host debe asociarlos a geometría y renderizarlos. |

## Participar como comunidad

El código del módulo tiene [licencia Apache-2.0](../LICENSE). Para facilitar otras
implementaciones, mantener versionados la especificación, ejemplos reproducibles
y vectores de aceptación/rechazo de los tests. Documentar qué perfil implementa
cada motor y qué no soporta. El formato binario no obliga a implementar el lector
en Dart, aunque el SDK de referencia actual usa Dart.

Antes de llamarlo estándar interoperable faltan un proceso público de cambios,
versiones estables, pruebas cruzadas con otra implementación y publicación de
esos materiales. Acortar el sufijo no sustituye ese trabajo. Durante esta primera
beta se mantienen `VRLW0001` y `schemaVersion: 1`: las ampliaciones necesitan
actualizar conjuntamente especificación, herramientas y pruebas de compatibilidad.
El lector admite únicamente las ampliaciones concretamente implementadas y
validadas en ese snapshot del SDK.
