/// Optional native storage for disposable, encoded world-region data.
///
/// Keep this import out of web builds. The regular `vrlizate_world.dart` entry
/// point remains independent of `dart:io`.
library;

export 'domain/models/vr_region_disk_cache_stats.dart';
export 'domain/services/vr_region_disk_cache.dart';
export 'domain/services/vrlw_file_source.dart';
export 'src/bundles/vrlw_file_source.dart';
export 'src/storage/region_disk_cache.dart';
