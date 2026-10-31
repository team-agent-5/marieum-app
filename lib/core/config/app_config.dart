/// Build-time configuration; endpoint values are supplied by the deployment.
class AppConfig {
  const AppConfig({
    required this.baseUrl,
    required this.wsUrl,
  });

  const AppConfig.fromEnvironment()
    : baseUrl = const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://unity-cohen-reality-lived.trycloudflare.com',
      ),
      wsUrl = const String.fromEnvironment('WS_BASE_URL');

  final String baseUrl;
  final String wsUrl;
}
