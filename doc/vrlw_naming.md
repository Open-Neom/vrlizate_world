# Nombres de archivo: `.vrlw`, `.vrw`, `.vrlz` y `.vrz`

Revisión: 8 de octubre de 2026. Recomendación técnica de esta revisión:
**conservar `.vrlw` para lugares y `.vrlz` para experiencias**. No se ha cambiado
el formato, añadido alias, renombrado archivos ni registrado un tipo MIME.

## Usos anteriores comprobados

| Sufijo | Evidencia del proveedor | Alcance de la conclusión |
| --- | --- | --- |
| `.vrz` | Siemens COMOS Walkinside documenta la publicación de proyectos VR en VRZ, con datos del proyecto y posibles logo, skybox y heightmap. Manual 03/2020 v10.3.3, sección 5.10, página impresa 102. | Existe una asociación previa directamente relacionada con realidad virtual y distribución de mundos. |
| `.vrw` | DataFlex Reports 2017 Developer Edition 6.0 identifica VRW como formato de reportes antiguos y documenta su migración a DR. Páginas 1 y 10 del readme oficial. | Existe un uso anterior documentado; la propia fuente lo describe como legado. |

Fuentes primarias: [Siemens COMOS Walkinside](https://cache.industry.siemens.com/dl/files/957/109778957/att_1017562/v1/COMOS_Walkinside_enUS_en-US.pdf)
y [DataFlex Reports 2017](https://www.dataaccess.eu/DataFlex-Reports-2017-Developer-Edition-Readme.pdf-f402).
Las fechas anteriores son las de las publicaciones, no las de su indexación
reciente por el buscador.

Esto demuestra usos previos, no una prohibición de reutilización ni una medición
de su popularidad actual. Tampoco demuestra qué admite la última versión comercial
de cada producto. Los listados genéricos de extensiones no se usaron como evidencia
principal. No se declara exclusividad ni disponibilidad universal de `.vrlw`.

## Evaluación de la abreviación

`.vrw` puede leerse fácilmente como «VR World», y `.vrz` es breve para un paquete.
Pero el ahorro de un carácter no mejora renderizado, compresión o streaming, y
puede generar ambigüedad en búsquedas, asociaciones del sistema y documentación.
La coincidencia de `.vrz` con un paquete VR ya existente merece especial atención.

La comunidad puede utilizar un formato con cuatro letras. Para facilitar adopción
resultan más útiles una especificación abierta a revisión, una implementación de
referencia, ejemplos, una licencia clara, pruebas de conformidad y compatibilidad
entre versiones. VRlizate puede impulsar ese trabajo sin presentar el formato
experimental como un estándar universal ya establecido.

Una denominación descriptiva como «paquete de mundo VR» puede acompañar a
`.vrlw` en la interfaz y la documentación. No hace falta exponer a cada usuario
los detalles del contenedor para que comparta un lugar.

## Extensión, formato y MIME son cosas distintas

- **Extensión:** sufijo utilizado por exportadores, filtros y asociaciones de
  archivos. El empaquetador actual exige `.vrlw`; la biblioteca `.vrlz` filtra
  su propio sufijo y no descubre mundos automáticamente.
- **Formato:** estructura y semántica de los bytes. VRLW v1 se identifica con
  `VRLW0001`, versión, índice, límites y hashes; un nombre de archivo no sustituye
  esas comprobaciones. Los lectores de bytes no necesitan el sufijo para validar
  contenido, aunque las herramientas de usuario sí puedan exigirlo.
- **MIME:** tipo declarado para transportar/identificar contenido. Este SDK no
  ha registrado uno específico. La distribución binaria puede usar
  `application/octet-stream`; un nombre MIME futuro necesita su proceso propio.

[RFC 6838, sección 5.6](https://www.rfc-editor.org/rfc/rfc6838.html#section-5.6)
distingue en la plantilla de registro los magic bytes y las extensiones, y el
[registro IANA de media types](https://www.iana.org/assignments/media-types/)
documenta el procedimiento de registro. No es un registro que asigne exclusividad
a todos los sufijos de archivos.

## Si después se decide cambiar el nombre

Esta es una ruta de migración propuesta, no implementada:

1. Elegir un sufijo canónico y documentar los usos ajenos que se deben distinguir.
2. Aceptar temporalmente sufijo antiguo y nuevo en los puntos de importación;
   verificar siempre el formato real antes de abrirlo.
3. Mantener cabecera, contenido, versión y hashes si solo cambia el nombre.
   Renombrar el archivo no altera los hashes de sus bytes. Cambiar URLs o nombres
   dentro de catálogos sí exige actualizar sus referencias y, cuando corresponda,
   firmas o hashes del propio catálogo.
4. Actualizar empaquetadores, catálogos, selectores, asociaciones, documentación
   y pruebas. Exportar con el nombre canónico y conservar lectura de los anteriores
   durante un periodo de compatibilidad definido.
5. Mantener las partidas ligadas a identidad/revisión/instancia, no al nombre del
   archivo ni a su ruta de descarga.

Cambiar la estructura para incluir recursos propios es una decisión distinta,
prevista en la [hoja de ruta de v1 beta](vrlw_beta_roadmap.md). Como el formato
todavía no se ha publicado, esas ampliaciones forman parte de la versión inicial
en desarrollo; requieren actualizar lectores, herramientas y pruebas de
compatibilidad, sin introducir campos silenciosamente.
Un `.vrz` de Siemens o un `.vrw` de DataFlex no se volverían compatibles con
VRlizate por compartir sufijo. Tampoco debe ofrecerse una conversión que no exista.
