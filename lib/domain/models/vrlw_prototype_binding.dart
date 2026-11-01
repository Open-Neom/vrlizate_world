import 'vrlw_collider_spec.dart';
import 'vrlw_lod_level.dart';

/// Declares static data for a prototype, not permission to instantiate it.
/// The host validates the model profile before registering the prototype.
final class VrlwPrototypeBinding {
  const VrlwPrototypeBinding({
    required this.prototypeId,
    required this.model,
    this.baseColorTexture,
    this.normalTexture,
    this.metallicRoughnessTexture,
    this.emissiveTexture,
    this.occlusionTexture,
    this.audio,
    this.collider,
    this.castsShadows,
    this.lods = const [],
    this.lodHysteresisMeters = 2,
  });

  final String prototypeId, model;
  final String? baseColorTexture;
  final String? normalTexture;
  final String? metallicRoughnessTexture;
  final String? emissiveTexture;
  final String? occlusionTexture;
  final String? audio;
  final VrlwColliderSpec? collider;
  final bool? castsShadows;

  /// Empty preserves the legacy single-detail model. Decoded lists are frozen.
  final List<VrlwLodLevel> lods;

  /// World meters on each side of a transition to avoid boundary oscillation.
  final double lodHysteresisMeters;

  Map<String, Object> toJson() => {
    'prototypeId': prototypeId,
    'model': model,
    if (baseColorTexture != null) 'baseColorTexture': baseColorTexture!,
    if (normalTexture != null) 'normalTexture': normalTexture!,
    if (metallicRoughnessTexture != null)
      'metallicRoughnessTexture': metallicRoughnessTexture!,
    if (emissiveTexture != null) 'emissiveTexture': emissiveTexture!,
    if (occlusionTexture != null) 'occlusionTexture': occlusionTexture!,
    if (audio != null) 'audio': audio!,
    if (collider != null) 'collider': collider!.toJson(),
    if (castsShadows != null) 'castsShadows': castsShadows!,
    if (lods.isNotEmpty) ...{
      'lods': lods.map((level) => level.toJson()).toList(),
      'lodHysteresisMeters': lodHysteresisMeters,
    },
  };
}
