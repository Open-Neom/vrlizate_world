/// Optional native storage for disposable, encoded world-region data.
///
/// Keep this import out of web builds. The regular `vrlizate_world.dart` entry
/// point remains independent of `dart:io`.
library;

export 'src/storage/region_disk_cache.dart';
export 'src/bundles/vrlw_file_source.dart';
