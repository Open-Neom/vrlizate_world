/// Content-addressed reference to an external/linked `.vrlw` world bundle.
final class VrlwWorldDependency {
  const VrlwWorldDependency({
    required this.alias,
    required this.id,
    required this.revision,
    required this.indexSha256,
    this.url,
  });

  final String alias;
  final String id;
  final String revision;
  final String indexSha256;
  final String? url;

  Map<String, Object> toJson() => {
    'alias': alias,
    'id': id,
    'revision': revision,
    'indexSha256': indexSha256,
    if (url != null) 'url': url!,
  };
}
