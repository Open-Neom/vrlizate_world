# VRLW v1 beta: lugares por regiones

`.vrlw` describe un lugar mediante coordenadas y objetos de prototipos validados
por el anfitrión, con recursos estáticos opcionales incluidos en el archivo. Complementa a `.vrlz`, que conserva sus perfiles de experiencias.
Compilar un lugar significa validar, indexar y comprimir su contenido. Al abrirlo,
VRlizate decodifica datos y descomprime regiones; no descompila ni ejecuta Dart
descargado. La extensión es una convención del SDK, no un registro exclusivo.

Para crear el primer paquete, seguir la [guía de autoría e integración](vrlw_guide.md).
La [evaluación de nombres y compatibilidad](vrlw_naming.md) conserva `.vrlw` y
`.vrlz` tras comprobar usos anteriores de `.vrw` y `.vrz`.

## Contenedor y acceso parcial

| Posición | Contenido |
| --- | --- |
| Bytes 0–7 | ASCII `VRLW0001`. |
| Bytes 8–11 | Longitud del índice JSON, entero sin signo de 32 bits little-endian. |
| Bytes 12–15 | Longitud total de los bloques empaquetados, mismo tipo. |
| Desde byte 16 | Índice JSON UTF-8, seguido por bloques de regiones y, opcionalmente, recursos. |

El índice declara `schemaVersion: 1`, `id`, `title`, `revision`, `license`,
`gridId`, `cellSizeMeters`, `prototypes`, `origin` y `chunks`. Cada chunk contiene
`x`, `z`, `offset`, `packedBytes`, `unpackedBytes`, `codec` y `sha256`.
El índice puede incluir además `resources`, `prototypeBindings`, `environment`,
`audioEmitters`, `dependencies`, `motions` e `interactions`. Todos tienen campos
y referencias explícitos; no existe una bolsa de componentes ejecutables.
Los offsets son relativos al inicio del área de bloques. Los bloques son
contiguos, sin huecos, superposiciones ni bytes finales ajenos al contenedor.

Cada región se comprime por separado con DEFLATE crudo, o se almacena con STORE
cuando comprimir no reduce su tamaño. El SHA-256 cubre sus bytes empaquetados y se
verifica antes de expandirlos. El índice frontal permite leer cabecera e índice y,
después, solamente el bloque solicitado. Comprimir todo el lugar como un único
flujo impediría este acceso independiente.

En el índice los valores literales de `codec` son `deflate` y `store` (minúsculas).
El índice no está comprimido; su hash cubre sus bytes UTF-8 exactos, no una
reserialización equivalente del JSON. El contenedor no es ZIP y no se extrae
como un directorio de archivos.

`VrlwPlaceReader.open` lee el índice y valida los prototipos registrados.
`VrlwRegionProvider` conecta el lector con `VrRegionCache`: demanda cercana,
precarga, retención, TTL/LRU y presupuestos de memoria. Sus callbacks de caché
conservan bloques comprimidos; un bloque corrupto se vuelve a solicitar.
Cerrar el lector invalida también resultados de caché que lleguen tarde.

## Autoría y coordenadas

El documento fuente usa los metadatos anteriores y una lista `regions` en lugar
de `chunks`. Cada región contiene `x`, `z` y `entities`. Cada entidad declara
`id`, `prototypeId`, `x`, `y`, `z`, y opcionalmente `yawRadians` y `scale`.
El bloque decodificado contiene únicamente `{"entities": [...]}`.

Las coordenadas X/Z de una entidad son locales a su región, desde cero hasta
antes de `cellSizeMeters`. El lector suma el desplazamiento de la celda. Y es
altura en el marco local, el giro es yaw en radianes y la escala es uniforme.
Las posiciones finales respetan los límites de `VrWorldPosition`.

El origen por defecto es `{"type":"local"}`: metros, +X derecha, +Y arriba,
−Z adelante. También se acepta metadata `wgs84-enu` con `latitudeDegrees`,
`longitudeDegrees` y `ellipsoidalHeightMeters`: +X este, +Y arriba y −Z norte.
Esto no descarga terreno ni transforma/recentra coordenadas automáticamente;
el host debe adoptar explícitamente esa referencia mediante `vrlizate_earth`.

El ID del mundo proviene del índice y la instancia pertenece al host. La
identidad efectiva de caché incluye el SHA-256 de los bytes del índice, por lo
que cambiar origen, contenido o revisión no mezcla regiones anteriores.

Los prototipos deben aparecer tanto en el índice como en el registro del host.
Pueden referenciar una representación ya instalada o declarar recursos estáticos
para que el host los valide y registre. Se admiten muestras de audio como datos y
los movimientos/acciones acotados descritos abajo; no se empaquetan scripts,
animales con comportamiento arbitrario ni simulaciones de clima. El renderizador sigue siendo
responsable de instancing, detalle y culling. Un archivo pequeño no garantiza
por sí mismo mayor FPS.

## Recursos estáticos opcionales de la beta

La fuente acepta `resources: [{id, type, data, width?, height?}]`, donde `data`
es base64 de los bytes originales. El codec general reconoce `model.glb`,
`texture.rgba8`, `texture.png`, `texture.jpeg`, `texture.ktx2`,
`environment.ktx2`, `audio.wav`, `audio.ogg` y `audio.mp3`. Cada consumidor aplica
su perfil más estrecho antes de importar o reproducir. RGBA8 requiere `width` y
`height` y exactamente `width × height × 4` bytes; texturas comprimidas pueden
declarar ambas dimensiones o ninguna. Audio, GLB y entorno no declaran esas
dimensiones. No hay rutas externas en los recursos ni resolución de URLs.

El índice compilado sustituye `data` por `offset`, `packedBytes`, `unpackedBytes`,
`codec` y `sha256`, conservando ID, tipo y dimensiones cuando corresponden. Los
bloques de recursos siguen a los de región, sin huecos ni superposición; cada
uno se comprime y verifica independientemente. `VrlwPlaceReader.readResource(id)`
lee únicamente ese bloque, con rangos acotados, y no retiene el resultado.

`prototypeBindings` requiere `prototypeId` y `model`; puede referenciar mapas
`baseColorTexture`, `normalTexture`, `metallicRoughnessTexture`, `emissiveTexture`,
`occlusionTexture`, además de `audio`, `collider` y `castsShadows`. Cada
prototipo vinculado debe estar declarado y no repetirse; las referencias deben
resolver recursos del tipo correspondiente. El perfil `.vrlz` de mundos exige
vincular todos sus prototipos. El lector general conserva la opción de prototipos
preinstalados sin vinculación.

`vrlizate_world` valida la envoltura GLB, tamaños, hashes y compresión; la validación
completa de geometría, atributos, referencias y extensiones corresponde al perfil
GLB de `vrlizate_apps` antes de crear recursos GPU. Las escenas VRZ siguen sin
texturas internas; el perfil de mundos permite PNG baseColor embebido con UV0
bajo sus límites. Ambos excluyen clips de animación glTF, skins y URLs. Las
texturas de un binding se aplican separadamente; no habilitan mapas internos
arbitrarios. El codec de World valida las declaraciones de movimiento, pero
no interpreta el grafo glTF ni demuestra por sí solo que el nodo animable exista.

Los paquetes anteriores sin estas tablas conservan sus bytes y compatibilidad
con el lector actualizado. Un lector anterior a esta ampliación beta rechaza los
campos nuevos. La cabecera y `schemaVersion` permanecen en 1; no se declara una
segunda versión publicada ni compatibilidad con todos los snapshots previos.

## Movimiento e interacciones declarativos

La fuente y el índice pueden declarar `motions` e `interactions`, con un máximo
de **ocho entradas por lista**. El compilador usa el mismo validador que el
lector; omite ambos arrays si quedan vacíos. Se mantiene `VRLW0001` y
`schemaVersion: 1`, en beta: los lectores anteriores que desconocen los nuevos
campos los rechazan. No son scripts, Dart compilado ni callbacks descargados.

```json
{
  "motions": [{
    "id": "courtyard.rotor", "prototypeId": "campus.landmark",
    "node": "rotor", "kind": "spin", "axis": "y",
    "pivot": [0, 3.2, 0], "periodSeconds": 12,
    "rangeMeters": 32, "initiallyEnabled": true
  }],
  "interactions": [{
    "id": "courtyard.switch", "label": "Rotor del patio",
    "position": [17, 1.2, 13], "maxDistance": 3,
    "action": "toggleMotion", "target": "courtyard.rotor"
  }]
}
```

El fragmento requiere un binding `campus.landmark` y una región que contenga la
posición. `VrlwMotionSpec` y `VrlwInteractionSpec` exponen estos datos mediante
las listas inmutables `VrlwBundleIndex.motions` e `interactions`; sus vectores son
copias inmutables. Las entidades regionales conservan su contrato estático:
identidad, prototipo y transformación; no aceptan componentes arbitrarios.

| Campo de motion | Contrato |
| --- | --- |
| `id`, `prototypeId`, `node` | Identificadores ASCII de hasta 128 caracteres; `prototypeId` exige binding GLB y cada ID es único. No se repite `(prototypeId, node)`. |
| `kind` | `spin` o `bob`. |
| `axis` | `x`, `y` o `z`, en el marco del modelo. |
| `pivot` | Tres números finitos de −32 a 32 m, por defecto `[0,0,0]`; centro del giro local. |
| `periodSeconds` | Obligatorio, finito, de 2 a 120 s. |
| `amplitude` | Obligatoria solo para `bob`: 0,001–0,5 m; se rechaza si `kind` es `spin`. |
| `rangeMeters` | 4–48 m, por defecto 32; radio para suspender actualización distante. |
| `initiallyEnabled` | Booleano, por defecto `true`. |

`spin` usa un giro positivo de `2π × tiempo / periodo`; `bob` usa un
desplazamiento `amplitude × sin(2π × tiempo / periodo)` en su eje. El giro se
aplica alrededor del pivote, antes de la pose de la entidad. No mueve colliders
ni aporta simulación de física. Un consumidor debe limitar además las instancias
activas y verificar la geometría objetivo.

| Campo de interacción | Contrato |
| --- | --- |
| `id` | Identificador ASCII único de hasta 128 caracteres. |
| `label` | Texto no vacío, hasta 80 caracteres, sin controles. |
| `position` | Tres números finitos en metros del mundo local, acotados por el marco World; X/Z dentro de una región indexada, excluyendo el borde superior. No son coordenadas relativas a la celda. |
| `maxDistance` | 0,25–4 m en 3D, por defecto 3. |
| `action`, `target` | `toggleMotion` exige un ID de motion existente; `toggleAudio`, un ID de `audioEmitters`. |

Se rechazan referencias cruzadas, IDs duplicados, tipos inválidos, campos
adicionales, posiciones sin región y números no finitos. El codec general
valida el dato; no autoriza la interacción ni ejecuta la acción al leerlo.

### Perfil móvil consumidor de Apps

Antes de importar recursos nativos o GPU, `VrlwMotionProfile` exige que el nombre
resuelva exactamente un nodo de todo el GLB. Debe ser una hoja con malla,
directamente en la escena activa, sin hijos y sin atributos `matrix`,
`translation`, `rotation` ni `scale` (identidad implícita). Se rechazan nombres
ausentes o duplicados, nodos de otra escena y padres transformados. No se añaden
clips glTF, skins ni un intérprete de código.

El adaptador mantiene geometría/materiales compartidos y limita a **16 las
instancias de primitivas móviles residentes**, incluyendo pausadas y lejanas;
varios materiales de una malla consumen varias primitivas. El control ocurre
antes de cambiar las instancias GPU. Los límites de escena siguen siendo 128
entidades, 256 primitivas y 80 000 triángulos residentes por escena/ojo. La
actualización de transformaciones es de hasta **30 Hz**; un track con alguna
instancia cercana avanza su fase y deja de actualizar instancias distantes.
Pausarlo conserva la pose, y varias instancias del mismo motion comparten fase.
Estos límites no garantizan FPS ni evitan medir el coste real en el teléfono.

El visor aplica alcance y cooldown de **0,4 s por control** a mirada, botón A y
tap. Conserva fase y toggles al regresar por portales durante esa instancia del
visor. No los escribe en `.vrlw`, en el snapshot persistente de pose/visitas ni
en un servicio multiusuario; otra instancia del visor reinicia ese estado.

El perfil móvil admite **ocho recursos no sonoros más un único `audio.wav`**;
ocho GLB con PNG embebido caben en ese presupuesto, mientras que las texturas
externas también ocupan entradas no sonoras. `VrlwAudioPolicy` restringe el WAV
a RIFF/WAVE canónico con `fmt ` PCM de 16 bytes y `data`: mono, PCM entero de
16 bits, blockAlign 2, **16 000 o 22 050 Hz**, byteRate `rate × 2`, hasta
**256 KiB y ocho segundos**, longitudes exactas y datos pares no vacíos. Ambos
límites se aplican: ocho segundos a 22 050 Hz pueden exceder los bytes permitidos.
No admite OGG, MP3, estéreo, float PCM ni chunks extra. World conserva su lector
general de audio; conocer un tipo no obliga al host a reproducirlo.

Los emisores existentes (`id`, `resource`, `x`, `y`, `z`, `volume`,
`maxDistance`, `loop`) comienzan habilitados; no se añadió `initiallyEnabled`
a ese contrato. `VrlzWorldViewer.audioOutputFactory` opta por reproducción nativa
mediante `VrlwAudioOutput`; sin factory no se crea salida. El controlador de Apps
usa una fuente y hasta **dos voces**, atenuación/pan estéreo, actualización
coalescida a **10 Hz** y suspensión al perder foco, ocultar la ruta, viajar o
salir. No es HRTF. El host VRlizate implementa el puerto con `neom_sound`/SoLoud,
compartiendo el motor existente y liberando solo sus fuentes/voces.

La [especificación de Apps](../../vrlizate_apps/doc/vrlz_format.md#movimiento-controles-y-audio-de-mundos-v1-beta)
y la [guía de la biblioteca](https://github.com/Open-Neom/codebase_vrlw/blob/main/docs/LIVING_WORLDS_MOBILE.md)
documentan la integración. Las pruebas de contrato no validan automáticamente
la presentación, el sonido o el rendimiento de un backend móvil.

## Validación y límites

| Recurso | Máximo v1 |
| --- | --- |
| Índice | 1 MiB |
| Regiones por archivo | 1,024 |
| Bloque regional empaquetado | 512 KiB |
| Bloque regional expandido | 2 MiB |
| Archivo completo | 128 MiB |
| Suma declarada de datos expandidos | 256 MiB |
| Entidades por región | 4,096 |
| Profundidad JSON | 12 |
| Recursos por lugar | 32 |
| Recurso expandido | 4 MiB |
| Suma de recursos expandidos | 16 MiB, también contabilizados en la cota total |
| Dimensión de textura RGBA8 | 512 × 512 como máximo |
| Vinculaciones de prototipo | 1,024 |
| Emisores de audio | 64 |
| Movimientos declarativos | 8 |
| Controles declarativos | 8 |

Se rechazan versiones, campos, coordenadas, tamaños y referencias incompatibles.
La inflación usa salida acotada y comprueba cada escritura; no se debe sustituir
por un decodificador nativo que reserve toda la expansión antes de validarla.
El proveedor conserva la ruta directa para bloques pequeños. Desde la
preview.7 del SDK, bloques de al menos 64 KiB expandidos se decodifican en un isolate
nativo; el umbral es una heurística, no una garantía de tiempo de frame. La fuente
web conserva decodificación en el hilo actual hasta disponer de un worker web.
La concurrencia del proveedor debe limitarse mediante la caché/planificador del
host. El isolate tiene coste de arranque y su cancelación descarta el resultado,
sin interrumpir forzosamente un bloque en curso. La creación GPU sigue a cargo
del renderizador y también necesita un presupuesto de incorporación por frame.

El compilador rechaza IDs de entidades duplicados entre regiones. La lectura
diferida valida duplicados dentro de cada bloque; al incorporar regiones externas, el
host debe usar el registro del mundo para rechazar duplicados entre regiones.

Los hashes internos detectan corrupción, no autentican autores. Un catálogo
confiable puede fijar `expectedIndexSha256`. La licencia declarada tampoco
demuestra derechos de distribución. Partidas, cambios del usuario y permisos
se mantienen fuera de la caché descartable y de este contenedor.

La ampliación declarativa del 25 de octubre de 2026 pasó 47 casos nuevos en
`test/vrlw_behaviors_test.dart`, dentro de un lote de **84** junto a
`vrlw_resources_test.dart` y `vrlw_bundle_test.dart`. Incluye compilación y lectura
estricta de los mismos negativos, límites 8/9, referencias, valores no finitos,
coordenadas negativas/bordes, inmutabilidad y bytes anteriores. El consumidor
Apps superó su ronda de 101 pruebas de lógica/perfil/presupuesto (incluye 42 de
actividad y perfil, más siete del límite móvil). Son evidencias previas a GPU,
no una medida de FPS, acústica ni calidad visual en dispositivo.

## Fuentes locales y HTTPS

- `VrlwMemorySource`: bytes en memoria; útil para assets y pruebas.
- `VrlwFileSource`: lecturas parciales nativas con cursor serializado; rechaza
  enlaces simbólicos y detecta cambios ordinarios de tamaño/fecha/tipo.
- `VrlwHttpSource`, en `vrlizate_apps`: HTTPS con rangos de bytes, respuesta 206
  y `Content-Range` exactos. Fija un ETag fuerte y envía `If-Match` después de la
  primera lectura. Rechaza cambios de versión, respuesta 200 completa,
  redirecciones, compresión de transporte y cuerpos fuera del presupuesto.

El hosting debe servir rangos sin alterar el contenedor. Para navegador, CORS
debe permitir `Range`/`If-Match` y exponer `ETag`, `Content-Range` y
`Content-Encoding`. La API no despliega ni configura un hosting.

La verificación de tamaño/fecha local detecta cambios habituales, no sustituye
una fuente confiable; cada bloque conserva su comprobación criptográfica.

## Herramientas y piloto del bosque

Desde `vrlizate_world`, después de `dart pub get`:

```sh
dart run tool/pack_vrlw.dart tool/fixtures/forest.vrlw.json /tmp/mi-bosque.vrlw
dart run tool/read_vrlw.dart /tmp/mi-bosque.vrlw 1 1
```

El empaquetador exige una salida nueva. La fuente editable y el archivo compilado
se distribuyen en `tool/fixtures/`. El ejemplo contiene 49 regiones de 12 metros:
**15,035 bytes**, frente a **28,667 bytes** para el mismo contenedor en STORE
(47.6% menos). Leer la celda (1, 1) consume 8,127 bytes de cabecera/índice y 143
bytes de región, sin leer los demás bloques. Estos tamaños son del piloto; no
predicen ahorros con texturas o audio ya comprimidos.

El bosque de OpenWorld en `VRlizate_app` consume una copia incluida como asset,
con índice fijado y prototipo `openworld.tree`. Flutter carga ese pequeño asset
completo una vez; luego se descomprimen solo las regiones solicitadas. Las fuentes
nativa y HTTPS sí permiten lectura parcial del contenedor. Fuera de las 49
regiones del piloto continúa la generación procedural existente. Se conservan
los grupos compartidos de render, niveles de detalle y caché de regiones.

La prueba HTTP completa verifica tres solicitudes (cabecera, índice, una región)
y que regresar después de retirar entidades de RAM reutiliza el bloque
comprimido sin otra descarga. No se ha cuantificado una mejora de FPS ni se ha
añadido un selector genérico de `.vrlw` al hub.

El 8 de octubre de 2026 se instaló el piloto en un Samsung S25 Ultra y se
comprobó visualmente Puerto Neom y Bosque en estéreo. Se recogieron tiempos de
los hilos UI/raster, sin una comparación A/B sostenida ni medida de finalización
GPU. Esa comprobación no cuantifica una mejora de FPS atribuible al formato.

Para cobertura terrestre, el siguiente nivel sería un catálogo jerárquico de
lugares y recursos compartidos; no un solo archivo planetario ni un índice con
todas las entidades del planeta.

## Referencias de interoperabilidad

La [autoría externa y el perfil de mundos](../../docs/creator_worlds_beta.md)
documentan el subconjunto implementado de GLB estático, RGBA8 y portales locales
declarados en `.vrlz`. La [hoja de ruta de VRLW v1 beta](vrlw_beta_roadmap.md)
conserva escenarios de evolución que deben leerse junto a este contrato
implementado. El audio y movimiento admitidos son únicamente los subconjuntos
acotados descritos aquí; no hay ejecución de código descargado.

El transporte sigue los [rangos HTTP de RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html#section-14).
[OGC 3D Tiles](https://www.ogc.org/standards/3dtiles/) y
[glTF 2.0](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html) son referencias
para futuros tiles y recursos 3D. `.vrlw` v1 no declara compatibilidad con ellos.
