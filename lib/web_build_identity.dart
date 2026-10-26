class WebBuildIdentity {
  static const id = String.fromEnvironment(
    'WEB_BUILD_ID',
    defaultValue: 'local-development',
  );
}
