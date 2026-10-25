import 'vrlw_audio_emitter.dart';
import 'vrlw_bundle_header.dart';
import 'vrlw_chunk_index.dart';
import 'vrlw_environment_spec.dart';
import 'vrlw_interaction_spec.dart';
import 'vrlw_motion_spec.dart';
import 'vrlw_prototype_binding.dart';
import 'vrlw_resource_index.dart';
import 'vrlw_world_dependency.dart';

/// Validated metadata. It does not retain compressed payload or decoded objects.
///
/// [indexSha256] identifies the exact index bytes and includes chunk digests;
/// hosts can use it to avoid stale cache entries when a publisher changes data.
/// Digests detect corruption, but are NOT publisher authentication or signatures.
final class VrlwBundleIndex {
  VrlwBundleIndex({
    required this.header,
    required this.id,
    required this.title,
    required this.revision,
    required this.license,
    required this.gridId,
    required this.cellSizeMeters,
    required Set<String> prototypeIds,
    required Map<String, Object?> origin,
    required this.indexSha256,
    required List<VrlwChunkIndex> chunks,
    required List<VrlwResourceIndex> resources,
    required List<VrlwPrototypeBinding> prototypeBindings,
    this.environment,
    List<VrlwAudioEmitter> audioEmitters = const [],
    List<VrlwMotionSpec> motions = const [],
    List<VrlwInteractionSpec> interactions = const [],
    List<VrlwWorldDependency> dependencies = const [],
  }) : prototypeIds = Set.unmodifiable(prototypeIds),
       origin = Map.unmodifiable(origin),
       chunks = List.unmodifiable(chunks),
       resources = List.unmodifiable(resources),
       prototypeBindings = List.unmodifiable(prototypeBindings),
       audioEmitters = List.unmodifiable(audioEmitters),
       motions = List.unmodifiable(motions),
       interactions = List.unmodifiable(interactions),
       dependencies = List.unmodifiable(dependencies),
       _resourcesById = {
         for (final resource in resources) resource.id: resource,
       },
       _byCell = {for (final chunk in chunks) (chunk.x, chunk.z): chunk};

  final VrlwBundleHeader header;
  final String id;
  final String title;
  final String revision;
  final String license;
  final String gridId;
  final double cellSizeMeters;
  final Set<String> prototypeIds;

  /// Schema v1 uses meters and Y-up. `local`: +X right, -Z forward.
  /// `wgs84-enu`: +X east, -Z north, Y ellipsoid-normal up; ellipsoidal height
  /// is NOT sea-level altitude. Earth hosts explicitly adopt this origin.
  final Map<String, Object?> origin;
  final String indexSha256;
  final List<VrlwChunkIndex> chunks;
  final List<VrlwResourceIndex> resources;
  final List<VrlwPrototypeBinding> prototypeBindings;
  final VrlwEnvironmentSpec? environment;
  final List<VrlwAudioEmitter> audioEmitters;
  final List<VrlwMotionSpec> motions;
  final List<VrlwInteractionSpec> interactions;
  final List<VrlwWorldDependency> dependencies;
  final Map<String, VrlwResourceIndex> _resourcesById;
  final Map<(int, int), VrlwChunkIndex> _byCell;

  VrlwChunkIndex? chunkAt(int x, int z) => _byCell[(x, z)];
  VrlwResourceIndex? resourceAt(String id) => _resourcesById[id];
}
