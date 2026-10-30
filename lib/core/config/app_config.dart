/// Build-time configuration; endpoint values are supplied by the deployment.
class AppConfig {
  const AppConfig({
    required this.baseUrl,
    required this.wsUrl,
    this.useMock = false,
    this.showSafetyBanner = true,
  });

  const AppConfig.fromEnvironment()
    : baseUrl = const String.fromEnvironment('API_BASE_URL'),
      wsUrl = const String.fromEnvironment('WS_BASE_URL'),
      useMock = const bool.fromEnvironment('USE_MOCK'),
      showSafetyBanner = const bool.fromEnvironment(
        'SHOW_SAFETY_BANNER',
        defaultValue: true,
      );

  final String baseUrl;
  final String wsUrl;
  final bool useMock;
  final bool showSafetyBanner;
}
