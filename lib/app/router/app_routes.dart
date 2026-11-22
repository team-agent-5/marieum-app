abstract final class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const signup = '/signup';
  static const onboarding = '/onboarding';
  static const speak = '/speak';
  static const playback = '/speak/playback';
  static const live = '/speak/live';

  /// The patient's code for the other phone.
  static const listenHost = '/speak/listen';

  /// Live mode with sentences sent to the other phone.
  static const liveRelay = '/speak/listen/live';

  /// The other phone, without a login.
  static const listener = '/listener';
  static const history = '/history';
  static const settings = '/settings';
  static const quickPhrases = '/quick-phrases';
  static const insight = '/insight';
  static const account = '/account';
  static const privacy = '/privacy';
}
