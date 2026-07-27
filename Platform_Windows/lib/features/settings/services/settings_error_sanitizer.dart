String sanitizeSettingsErrorForUser(Object error) {
  var sanitized = error.toString().replaceFirst(
        RegExp(r'^(Bad state|Exception|FormatException):\s*'),
        '',
      );
  sanitized = sanitized.replaceAll(
    RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
    'Bearer <redacted>',
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(
      r'([?&](?:pin|token|access_token|refresh_token|client_secret|password)=)'
      r'[^&\s]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}<redacted>',
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(
      r'''(["']?(?:access_token|refresh_token|client_secret|password|apikey|api_key|authorization|pin|token)["']?\s*[:=]\s*)["']?[^"',}&\s]+''',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}<redacted>',
  );
  sanitized = sanitized.replaceAll(
    RegExp(r'(/Users/|/private/var/|/var/folders/)[^\s,;)\]}]+'),
    '<local-path>',
  );
  sanitized = sanitized.replaceAll(
    RegExp(r'[A-Z]:\\Users\\[^ \t\r\n,;)\]}]+', caseSensitive: false),
    '<local-path>',
  );
  return sanitized;
}
