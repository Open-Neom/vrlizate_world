import 'vrlw_collider_spec.dart';

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
  };
}
