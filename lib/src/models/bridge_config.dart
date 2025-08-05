class BridgeConfig {
  final String baseUrl;
  final Map<String, String> headers;
  final bool enableJavaScript;
  final bool enableCache;
  final Duration cacheTimeout;
  final List<String> allowedDomains;
  final Map<String, dynamic> initialData;

  const BridgeConfig({
    required this.baseUrl,
    this.headers = const {},
    this.enableJavaScript = true,
    this.enableCache = true,
    this.cacheTimeout = const Duration(hours: 1),
    this.allowedDomains = const [],
    this.initialData = const {},
  });

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'headers': headers,
        'enableJavaScript': enableJavaScript,
        'enableCache': enableCache,
        'cacheTimeout': cacheTimeout.inMilliseconds,
        'allowedDomains': allowedDomains,
        'initialData': initialData,
      };
}
