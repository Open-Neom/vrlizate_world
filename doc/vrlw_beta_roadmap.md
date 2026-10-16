# VRLW v1 beta: recursos espaciales y mundos conectados

Estado: **hoja de ruta de la primera versión en desarrollo, VRLW v1 beta**.
Actualizada el 10 de octubre de 2026. VRLW todavía no tiene una versión estable
publicada. La base implementada y las ampliaciones pendientes se distinguen aquí:
el subconjunto de recursos estáticos y portales locales ya tiene implementación;
los contratos remotos, formatos adicionales y montajes de esta hoja de ruta
siguen requiriendo implementación y pruebas antes de ser aceptados. No representan mejoras de FPS
medidas en un teléfono.

## Base implementada y evolución durante la beta

El formato implementado se describe en [VRLW v1](vrlw_format.md). Su cabecera es
`VRLW0001`; el índice conserva un esquema cerrado de metadatos, prototipos,
regiones y las tablas opcionales `resources` y `prototypeBindings`. Cada entidad
contiene identidad, posición, yaw y escala uniforme. Los recursos admitidos son
GLB estático y texturas RGBA8 acotadas; el host valida y registra sus prototipos.
Audio, comportamientos y dependencias remotas aún no se empaquetan.

El perfil `.vrlz` `vrlizate.worlds.v1` ya permite mundos locales incluidos en el
paquete y portales entre ellos, con IDs, hashes y llegadas verificados. Esto no
amplía los campos de otros perfiles ni habilita dependencias remotas, permisos o
archivos arbitrarios. La [guía de autoría externa](../../docs/creator_worlds_beta.md)
describe lo implementado; el resto de este documento propone su evolución.

Se mantiene una sola versión inicial: **VRLW v1 beta**, con cabecera `VRLW0001`
y `schemaVersion: 1`. Esta hoja de ruta no cambia sus bytes ni habilita campos
nuevos. Antes de incorporar una ampliación durante la beta deben actualizarse
juntos la especificación, el empaquetador, el lector, las capacidades del host y
los ejemplos. Cada cambio necesita pruebas de aceptación/rechazo y compatibilidad
con los paquetes beta existentes; cuando corresponda, se regeneran esos paquetes
y se documenta qué revisión del SDK los acepta. Los lectores anteriores siguen
rechazando campos desconocidos.

El contrato `.vrlz` de mundos utiliza un perfil y runtime registrados
explícitamente: `vrlizate.worlds.v1`. Las dependencias remotas requieren otra
capacidad validada dentro de la beta, sin ampliar silenciosamente la semántica
de `worlds.local` ni de los perfiles existentes. Antes de una publicación estable se debe fijar una política
de compatibilidad para las futuras versiones públicas.

Compilar significa validar, preparar niveles de detalle, indexar y comprimir
datos. Ninguno de estos formatos concede ejecución de Dart descargado,
bibliotecas nativas, shaders arbitrarios ni scripts embebidos.

## Experiencias que solicitan mundos

El perfil local implementado incluye sus lugares dentro del paquete. Como
ampliación futura, una experiencia podría declarar lugares remotos y solicitar
al host abrirlos.
La plataforma conserva el control del transporte, las credenciales, los límites,
los permisos y el ciclo de vida. El archivo describe la solicitud; no descarga
ni ejecuta otros paquetes por su cuenta.

El contrato propuesto para cada referencia contiene:

| Campo conceptual | Regla |
| --- | --- |
| Alias de dependencia | Único dentro de la experiencia; no es una ruta de disco. |
| Identidad y revisión | ID con namespace del editor y revisión inmutable. |
| Localizador | ID de catálogo resuelto por el host; alternativamente HTTPS dentro de orígenes autorizados. |
| Integridad | SHA-256 del índice esperado, fijado en un catálogo confiable o manifiesto autenticado. |
| Compatibilidad | Versión de contenedor, perfil y capacidades mínimas. |
| Uso | Obligatorio u opcional, punto de entrada y política de carga bajo demanda. |
| Presupuesto | Tamaño esperado y máximo admitido por el host; la declaración no puede elevar su cuota. |

El índice verificado debe fijar hashes de todos los bloques y recursos alcanzables.
Un hash dentro del mismo archivo detecta corrupción pero no demuestra quién lo
publicó. La autenticación corresponde al catálogo/firmante confiable. Un ETag
fuerte evita mezclar lecturas de dos revisiones HTTP; no sustituye esa confianza.
El transporte actual ya exige rangos exactos y versión estable siguiendo
[RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html#section-14).

Una dependencia no hereda acceso al micrófono, cámara, contactos, cuenta ni red
general. El host decide qué servicios existentes de Open Neom se exponen. Un
lugar público tampoco obtiene autoridad para modificar presencia, partidas o
inventario de sus visitantes. Esas operaciones mantienen sus reglas de servicio.

## Índice de recursos y carga parcial

El índice frontal debe separar tres tablas: regiones, recursos y vínculos a otros
lugares. Los objetos referencian IDs de recursos/prototipos; nunca rutas o URLs
interpretadas libremente por el renderizador.

Cada recurso declara ID, tipo/perfil, versión, bytes almacenados, bytes expandidos,
hash, bloques que lo componen y dependencias locales. La metadata específica
incluye dimensiones/mips en texturas; vértices, índices, primitivas y materiales
en modelos; duración/canales/frecuencia en audio; y formas/límites en colisiones.
El compilador obtiene esos datos del contenido y el lector los vuelve a validar.

Los bloques mantienen acceso independiente, offsets acotados, ausencia de
superposición/huecos inesperados y verificación antes de descomprimir. Recursos
grandes necesitan bloques o páginas propias; no deben forzar a descargar todos
los recursos de una región. Imágenes o audio ya comprimidos normalmente usarán
STORE si otra compresión no reduce su tamaño. El formato no garantiza el ahorro
del piloto del bosque para archivos multimedia.

Una misma geometría, textura o pista debe almacenarse una vez y ser referenciada
por varias entidades/regiones. La caché de contenido puede deduplicar por hash,
tipo y versión del decodificador, manteniendo permisos separados para contenido
privado. El renderizador debe compartir los recursos GPU compatibles.

No se extraen nombres no confiables directamente al sistema de archivos. Si un
adaptador necesita archivos temporales, el host genera los nombres dentro de un
directorio propio y prohíbe rutas absolutas, `..`, enlaces y escrituras fuera de él.
La validación debe rechazar referencias ausentes, IDs repetidos, tamaños falsos,
profundidad excesiva, extensiones requeridas desconocidas y bombas de expansión.

## Capacidades reales y perfiles propuestos

El soporte de una biblioteca subyacente no implica que el formato de VRlizate
admita cualquier archivo que esa biblioteca pueda abrir.

| Contenido | Verificado hoy | Ampliación pendiente de la beta |
| --- | --- | --- |
| Entidades y prototipos registrados | VRLW v1 los admite. | Conservar un perfil mínimo portable. |
| GLB/glTF 2.0 | VRLW admite recursos `model.glb`; el runtime de mundos valida el mismo subconjunto estático que escenas: sin texturas internas, animaciones, skins ni URLs externas. | Empezar con GLB estático acotado y recursos autocontenidos; ampliar capacidades con validadores específicos. |
| Imágenes y materiales | VRLW admite `texture.rgba8` y vínculo de color base; todavía no empaqueta PNG/JPEG ni mapas PBR adicionales. | Validar firmas, dimensiones, canales, mips y presupuesto de expansión antes de crear texturas. Definir espacio de color por uso. |
| Texturas comprimidas | Flutter Scene 0.22.2 incluye `.fstex`, con un payload propio dentro de KTX2. El Thermion local expone `loadKtx2`. | Mantener perfiles por backend y variantes compatibles. No declarar `.fstex` intercambiable con KTX2/Basis Universal ni habilitarlo solo por la extensión. |
| Audio ambiental | `vrlizate_spatial_audio` calcula política/atenuación; no captura ni reproduce audio. | Recursos y emisores declarativos reproducidos por adaptadores existentes, con codecs comprobados por plataforma. |
| Colisión y física | Hay módulos y tipos propios del SDK; VRLW v1 no transporta sus datos. | Formas simples/colliders simplificados con unidades y límites; no aceptar un motor o comportamiento descargado. |
| Animación, navegación y terreno | No están implementados como recursos VRLW. | Capacidades futuras independientes; cada una exige esquema, lector, límites y pruebas. |

El importador local de Scene examinado lee `texture.source` y no implementa en
esa ruta `KHR_texture_basisu`. Encontrar código KTX2 en el paquete no acredita esa
extensión glTF. En el estándar, Basis Universal requiere un perfil y declaraciones
de extensión concretos; un recurso obligatorio no puede ignorarse silenciosamente.
Véanse [glTF 2.0](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html) y
[KHR_texture_basisu](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_texture_basisu/README.md).

Las variantes deben expresar capacidades requeridas, fallback explícito y un
resultado visual comparable. Antes de importar un GLB se debe validar también
cualquier URI o recurso anidado: GLB no garantiza por sí solo autocontención.

## Coordenadas, identidad y portales

Conservar metros, +Y arriba y la convención local documentada de +X derecha,
−Z adelante. Cada lugar define origen y marco. El perfil terrestre declara
referencia geodésica y transformación explícita; la etiqueta WGS84 sola no
proyecta la geometría ni evita la pérdida de precisión de la GPU.

La identidad de una entidad cargada debe incluir al menos experiencia propietaria,
worldId, instanceId asignado por el host, revisión/hash, mountId y entityId local.
`VrWorldAddress` hoy contiene solo worldId e instanceId: el aislamiento por editor,
experiencia y montaje es una responsabilidad pendiente de la capa de composición.
Un paquete no puede elegir una instancia privada de otro usuario para integrarse
a ella sin autorización del servicio correspondiente.

Un montaje aditivo declara la transformación entre marcos, incluyendo escala
solo cuando el perfil la permita. Se valida la posición final y el volumen
transformado. Para lugares muy grandes se usan orígenes locales/recentrado,
evitando enviar coordenadas planetarias enormes directamente a vértices GPU.

Un portal declara destino, punto de llegada seguro, orientación y modo de
transición. El host resuelve el destino, verifica acceso y registra contexto de
regreso. Atravesarlo permite suspender el mundo anterior; ver un portal no debe
activar simulaciones completas de todos sus destinos.

Los ciclos entre portales, como A → B → A, son válidos para navegación. Los ciclos
entre dependencias de recursos obligatorias se rechazan. No se recorre el grafo
de portales como una orden de precarga recursiva. Las instancias públicas y
privadas pueden compartir bytes estáticos, pero no sus estados mutables.

## Presupuestos, LOD y criterios de FPS

Separar cuatro cantidades: transferencia comprimida, bytes descomprimidos del
contenedor, memoria CPU del recurso decodificado y memoria GPU. Una textura
RGBA8 de 2048 × 2048 ocupa 16 MiB en su nivel base, aunque su PNG pese poco;
una cadena completa de mips suma aproximadamente un tercio adicional. Las
reservas temporales de decodificación y subida también cuentan.

El límite actual `VrRegionData.sizeBytes` es una estimación de entidades; no mide
texturas, buffers ni recursos del driver. Una caché pequeña por mundo tampoco
limita el total cuando hay varios mundos montados. Se necesita un coordinador
global de CPU/GPU, transferencias, trabajos de decodificación y simulación.

| Límite | Base v1 beta implementada | Ampliación propuesta de la beta |
| --- | --- | --- |
| Índice / archivo completo | 1 MiB / 128 MiB | Conservar inicialmente. |
| Regiones / entidades por región | 1,024 / 4,096 | Conservar como máximos de formato; el host puede admitir menos. |
| Bloque empaquetado / expandido | 512 KiB / 2 MiB | Conservar por bloque; paginar recursos mayores con límite total propio. |
| Suma declarada expandida | 256 MiB | Conservar como cota del contenedor; no es una cuota de memoria residente. |
| Recursos y aristas de dependencia | 32 recursos por VRLW, 4 MiB por recurso expandido y 16 MiB en total; sin grafo genérico de dependencias | Propuesta inicial: hasta 1,024 recursos y 4,096 aristas por paquete. |
| Profundidad de dependencia obligatoria | No existe | Propuesta inicial: 4 niveles, con detección de ciclos. |
| Montajes simultáneos | El visor de mundos abre un destino activo; no hay composición aditiva genérica | Propuesta inicial: 1 mundo activo y hasta 1 destino en preparación. |
| Cuotas CPU/GPU y carga por frame | No se miden desde VRLW | Definir por perfil del dispositivo a partir de mediciones; las declaraciones del autor no conceden más cuota. |

Los valores nuevos son límites de diseño propuestos, **no resultados de pruebas**
ni garantías para Motorola/Samsung. Para la escena visible se deben presupuestar
primitivas, materiales, draw calls, transparencias, luces, sombras, instancias,
texturas y voces activas. Un paquete puede ser válido y exceder el perfil de un
dispositivo; debe seleccionar un LOD inferior o fallar con causa clara.

Cada recurso renderizable necesita volumen conservador y niveles de detalle
ordenados, con umbrales de error en pantalla o distancias e histéresis. Los bounds
deben incluir escala, animación y movimiento admitidos; bounds pequeños falsos
causan desapariciones incorrectas. El compilador los calcula/verifica frente al
contenido. La organización jerárquica y selección por región pueden inspirarse
en [OGC 3D Tiles](https://www.ogc.org/standards/3dtiles/), sin declarar compatibilidad
con ese estándar hasta implementar su contrato.

Las técnicas que afectan directamente el trabajo por cuadro son culling por ojo,
LOD, instancing/batching, materiales compartidos, límites de sombras/transparencias
y resolución apropiada. La compresión afecta transferencia y almacenamiento;
su decodificación puede producir tirones si compite con el hilo de interfaz.
Se deben separar descargas, validación/decodificación y creación GPU, con colas
acotadas, cancelación y presupuesto de trabajo antes de cada montaje.

Colisión, audio y visualización tienen vecindarios distintos. Un collider detrás
del usuario puede seguir siendo necesario; una fuente de sonido audible tampoco
debe desaparecer al salir del campo visual. Usar colliders simples cercanos,
limitación de voces por distancia/prioridad y simulación reducida en zonas
distantes. Atenuar audio no implica pausar automáticamente su cronología; el
adaptador debe conservar el estado requerido por cada experiencia.

Validar rendimiento con la misma ruta/cámara, configuración gráfica y contenido,
en modo profile/release. Registrar tiempo de frame p50/p95/p99, cuadros fuera del
presupuesto, CPU/raster/GPU cuando la plataforma lo permita, memoria residente,
trabajo de decodificación, subidas GPU y temperatura durante recorridos sostenidos.
60 FPS requieren entregar cuadros aproximadamente cada 16.7 ms; reducir bytes
del archivo no demuestra por sí mismo alcanzar ese objetivo.

## Ciclo de vida y caché

El host mantiene estados explícitos: solicitado, índice validado, recursos en
preparación, montado, suspendido y liberado. La transición de portal verifica la
nueva escena antes de retirar la anterior y cancela respuestas tardías mediante
identidad/generación de carga. Un fallo no debe dejar un montaje parcialmente
activo ni conservar su audio, colisiones o recursos GPU indefinidamente.

Separar caché comprimida en disco, recursos CPU decodificados, recursos GPU y
estado persistente del usuario. Las tres primeras son descartables por TTL/LRU;
partidas, contexto de regreso, objetos del usuario y permisos quedan en sus
servicios durables. Un recurso compartido se libera cuando no quedan montajes
que lo referencien. El presupuesto global incluye destinos precargados.

Al actualizar un lugar, nuevas lecturas usan una nueva revisión/hash; las sesiones
activas pueden terminar con la anterior. La recolección retira revisiones sin
referencias. Contenido privado necesita autorización vigente al abrirlo y una
política explícita de caché por cuenta; poseer bytes no concede derecho de acceso.

## Secuencia mínima reutilizable

1. Base implementada: referencias locales a mundos desde `vrlizate.worlds.v1`,
   con identidad y hashes. Pendiente: referencias HTTPS, permisos y capacidades
   entre experiencias, reutilizando los lectores y fuentes existentes.
2. Base implementada: portales locales y contexto de navegación separado de la
   caché. Pendiente: composición aditiva con namespace, cuotas globales y montajes
   de experiencias independientes.
3. Base implementada: GLB estático, RGBA8 y vinculaciones explícitas en v1 beta.
   Ampliar los perfiles solo después de compartir validadores y probar
   compatibilidad con los paquetes existentes.
4. Añadir el registro/adaptadores de recursos del renderizador y su coordinador
   global de memoria/carga. Incorporar texturas, audio y física por capacidades.
5. Con mediciones de teléfono, publicar perfiles de calidad y pruebas de rechazo,
   cancelación, recursos compartidos, revisiones, ciclos y retornos por portal.

Esta secuencia permite ampliar una experiencia con lugares bajo demanda sin
reimplementar transporte/caché ni convertir cada mundo en un runtime autónomo.
