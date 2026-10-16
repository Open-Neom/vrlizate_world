# Recursos estáticos de VRLW v1 beta

La beta mantiene la cabecera `VRLW0001` y `schemaVersion: 1`. El índice y la
fuente aceptan ahora dos campos opcionales: `resources` y `prototypeBindings`.
Al omitirlos, el empaquetador conserva exactamente los bytes del formato anterior,
tanto en STORE como en DEFLATE. Los lectores anteriores rechazan estos campos;
el anfitrión debe declarar que soporta este perfil de recursos antes de abrirlo.

El contenedor distribuye datos. No instala código Dart, bibliotecas nativas,
shaders, scripts ni importadores. El anfitrión conserva el registro de prototipos,
los permisos y los presupuestos de memoria, renderizado y transferencia.

## Fuente de autoría

Junto a los metadatos, `prototypes` y `regions` existentes:

```json
{
  "resources": [
    {"id": "chair-model", "type": "model.glb", "data": "BASE64_DEL_GLB"},
    {
      "id": "chair-color", "type": "texture.rgba8",
      "width": 1, "height": 1, "data": "/wAA/w=="
    }
  ],
  "prototypeBindings": [
    {
      "prototypeId": "furniture.chair",
      "model": "chair-model",
      "baseColorTexture": "chair-color"
    }
  ]
}
```

El fragmento se incorpora a una fuente completa; `BASE64_DEL_GLB` es un marcador.
`furniture.chair` debe estar declarado en `prototypes`. Un recurso puede compartirse
entre varios prototipos. Un prototipo tiene como máximo un binding. Los recursos
no referenciados pueden permanecer en el índice y no se descargan automáticamente.
Los prototipos sin binding continúan requiriendo una implementación del anfitrión.

Los IDs siguen las reglas existentes del SDK. Se rechazan recursos o bindings
duplicados, referencias ausentes, roles cruzados, campos desconocidos, dimensiones
inválidas y tipos no admitidos. `baseColorTexture` es opcional; si está presente,
debe ser un ID de textura, no `null`.

## Perfiles admitidos y validación

| Tipo | Datos | Comprobación en World |
| --- | --- | --- |
| `model.glb` | GLB 2.0 autocontenido para el perfil estático del anfitrión. | Cabecera, versión, longitud exacta y exactamente un bloque JSON y uno BIN alineados. No admite dimensiones de textura en su entrada. |
| `texture.rgba8` | Píxeles sin cabecera: cuatro bytes R, G, B, A por píxel; filas de arriba a abajo, de izquierda a derecha. | Ancho/alto enteros y longitud exacta `width × height × 4`. |

Los píxeles se entregan sin transformar: el adaptador debe aplicar la convención
de color y alpha del renderizador de manera explícita. El formato no aporta un
perfil ICC ni conversión automática de color.

**La validación de GLB en World comprueba solamente la envoltura binaria.** Antes
de registrar un binding o enviar sus bytes a un importador GPU, Apps/anfitrión
debe ejecutar la validación completa del perfil estático: JSON, geometría,
atributos, límites, extensiones y ausencia de referencias externas. El validador
`validateVrzGlb` existente en Apps cubre ese subconjunto; World no depende de
Flutter ni de Apps y no lo replica.

La textura externa del binding se aplica mediante el adaptador del anfitrión;
no habilita texturas, URLs, animación ni scripts internos arbitrarios del GLB.
Superar los límites de formato tampoco demuestra que un teléfono pueda mantener
una tasa de cuadros determinada.

## Índice y disposición de bloques

Todas las regiones preceden a todos los recursos en el payload. Una entrada de
recurso contiene `id`, `type`, `offset`, `packedBytes`, `unpackedBytes`, `codec`
y `sha256`; las texturas añaden `width` y `height`. No contiene `data` base64.
`offset` es relativo al comienzo del payload, igual que en las regiones.

Los bloques son contiguos, ordenados, sin solapamientos, huecos ni bytes sobrantes.
Cada recurso usa STORE o DEFLATE crudo de manera independiente. El compilador
elige DEFLATE solo cuando ahorra bytes. El SHA-256 corresponde al bloque
empaquetado; el hash del índice fija las tablas y todos esos hashes. Esto permite
detectar alteraciones; la identidad del autor depende del catálogo o del canal
de confianza del anfitrión.

| Límite | Valor |
| --- | --- |
| Recursos por archivo | 32 |
| Bytes empaquetados por recurso | 4 MiB |
| Bytes expandidos por recurso | 4 MiB |
| Suma de recursos expandidos | 16 MiB |
| Dimensión de textura | 1–512 píxeles por eje |
| Bindings | Máximo uno por prototipo declarado; hasta 1,024 |
| Lectura individual de la fuente | Hasta 1 MiB; recursos mayores requieren varios rangos |

Se conservan además el índice de 1 MiB, el archivo de 128 MiB y la cota global
expandida de 256 MiB que incluye regiones y recursos. La descompresión comprueba
el límite antes de cada escritura. Se rechazan datos truncados, bytes añadidos
a DEFLATE y expansión superior a la declarada.

## Lectura y responsabilidad del anfitrión

`VrlwBundleIndex.resources` y `prototypeBindings` son listas inmutables.
`resourceAt(id)` busca la entrada validada. `VrlwPlaceReader.readResource(id)`
lee únicamente el bloque solicitado, comprueba longitud, hash, expansión y
envoltura, y devuelve `Uint8List`. Las lecturas tardías después de `close()` se
rechazan. El lector no retiene recursos decodificados ni inicia solicitudes a URLs
que aparezcan en el contenido.

`VrlwBundleCodec.decodeResource(index, resource, packedBytes)` permite validar
un bloque antes de crear el lector de entidades. Rechaza una entrada de recurso
perteneciente a otro índice, aunque sus valores coincidan.

`VrlwPlaceReader.open` conserva la exigencia de `registeredPrototypeIds`:
un binding no registra por sí solo su prototipo. Para importar prototipos nuevos,
Apps puede leer el índice, comprobar los recursos con el codec, validar el perfil
GLB, crear adaptadores admitidos y finalmente abrir el lector con ese registro.

La caché de recursos, la creación de texturas/modelos GPU, su reutilización y la
cancelación del montaje pertenecen al anfitrión. Los recursos se decodifican en
el isolate llamador; esta API aún no tiene la delegación de bloques grandes que
sí posee el proveedor de regiones. El anfitrión debe preparar recursos antes de
montar la escena y medir su coste; no se afirma una mejora de FPS por este cambio.

Validación: `dart test test/vrlw_resources_test.dart`. Incluye compatibilidad de
bytes anteriores, STORE/DEFLATE, lectura parcial, propietario de índices,
alteraciones, límites, bombas de expansión, bindings y cierre durante una lectura.
