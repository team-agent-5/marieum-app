/// Build-time configuration; endpoint values are supplied by the deployment.
class AppConfig {
  const AppConfig({
    required this.baseUrl,
    required this.wsUrl,
    this.copaApiKey = '',
  });

  const AppConfig.fromEnvironment()
    : baseUrl = const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://unity-cohen-reality-lived.trycloudflare.com',
      ),
      wsUrl = const String.fromEnvironment('WS_BASE_URL'),
      copaApiKey = const String.fromEnvironment('COPA_API_KEY');

  final String baseUrl;
  final String wsUrl;

  /// Foundation media gateway key for cloud voices; empty uses the device
  /// voice only.
  final String copaApiKey;
}
