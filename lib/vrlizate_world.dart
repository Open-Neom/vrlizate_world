/// Render-neutral, local entity placement. This library does not synchronize
/// participants or authorize remote writes.
library;

export 'src/world_address.dart';
export 'src/world_entity.dart';
export 'src/world_registry.dart';
export 'src/streaming/region_cache.dart';
export 'src/bundles/vrlw_bundle.dart';
export 'src/bundles/vrlw_byte_source.dart';
export 'src/bundles/vrlw_chunk_decoder.dart';
export 'src/bundles/vrlw_region_provider.dart';
