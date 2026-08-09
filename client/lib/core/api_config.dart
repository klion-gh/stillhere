/// Backend endpoints. Point these at your deployed VPS before building
/// release binaries (e.g. https://chat.example.com and wss://chat.example.com).
class ApiConfig {
  static const String httpBaseUrl = String.fromEnvironment(
    'STILLHERE_HTTP_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const String wsBaseUrl = String.fromEnvironment(
    'STILLHERE_WS_BASE_URL',
    defaultValue: 'ws://localhost:3000',
  );
}
