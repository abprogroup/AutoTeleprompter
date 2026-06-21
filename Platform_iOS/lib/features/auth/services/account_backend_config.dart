const accountBackendEnabled = bool.fromEnvironment(
  'ACCOUNT_BACKEND_ENABLED',
  defaultValue: false,
);

const accountBackendSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const accountBackendAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

class AccountBackendConfig {
  final bool enabled;
  final String supabaseUrl;
  final String anonKey;

  const AccountBackendConfig({
    this.enabled = accountBackendEnabled,
    this.supabaseUrl = accountBackendSupabaseUrl,
    this.anonKey = accountBackendAnonKey,
  });

  bool get isConfigured =>
      enabled && supabaseUrl.trim().isNotEmpty && anonKey.trim().isNotEmpty;

  Uri authUri(String path) {
    final base = _baseUri();
    return base.replace(path: _joinPath(base.path, 'auth/v1/$path'));
  }

  Uri functionUri(String functionName) {
    final base = _baseUri();
    return base.replace(
        path: _joinPath(base.path, 'functions/v1/$functionName'));
  }

  Uri _baseUri() {
    if (supabaseUrl.trim().isEmpty) {
      throw StateError('Account backend URL is not configured.');
    }
    return Uri.parse(supabaseUrl.trim());
  }

  static String _joinPath(String basePath, String suffix) {
    final cleanBase = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    return '$cleanBase/$suffix';
  }
}
