import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/security/encrypted_file_store.dart';
import '../../auth/services/account_backend_config.dart';
import '../../auth/services/account_backend_service.dart';
import 'lightweight_diagnostics.dart';

const feedbackEndpoint = String.fromEnvironment('FEEDBACK_ENDPOINT');

class FeedbackSendResult {
  final bool sent;
  final bool queued;
  final String reportId;
  final String message;
  final String? failureClass;

  const FeedbackSendResult({
    required this.sent,
    required this.queued,
    required this.reportId,
    required this.message,
    this.failureClass,
  });
}

class FeedbackOutboxRetryResult {
  final int sent;
  final int remaining;
  final String message;

  const FeedbackOutboxRetryResult({
    required this.sent,
    required this.remaining,
    required this.message,
  });
}

class FeedbackReportService {
  static const int inlinePayloadThresholdBytes = 48 * 1024;
  static const int maxPendingReports = 3;
  static const int maxRedirects = 5;
  static const Duration defaultRequestTimeout = Duration(seconds: 20);

  FeedbackReportService({
    HttpClient? client,
    Future<Directory> Function()? outboxDirectory,
    String endpoint = feedbackEndpoint,
    AccountBackendConfig accountBackendConfig = const AccountBackendConfig(),
    AccountBackendService? accountBackendService,
    this.requestTimeout = defaultRequestTimeout,
  })  : _client = client ?? HttpClient(),
        _outboxDirectory = outboxDirectory,
        _endpoint = _sanitizeEndpoint(endpoint),
        _accountBackendConfig = accountBackendConfig,
        _accountBackendService = accountBackendService ??
            AccountBackendService(config: accountBackendConfig),
        _encryptedStore = EncryptedFileStore(baseDirectory: outboxDirectory);

  final HttpClient _client;
  final Future<Directory> Function()? _outboxDirectory;
  final String _endpoint;
  final AccountBackendConfig _accountBackendConfig;
  final AccountBackendService _accountBackendService;
  final Duration requestTimeout;
  final EncryptedFileStore _encryptedStore;

  static String _sanitizeEndpoint(String endpoint) =>
      endpoint.replaceAll(RegExp(r'[\r\n]'), '').trim();

  Future<FeedbackSendResult> submit(Map<String, Object?> report) async {
    final reportId = report['reportId']?.toString() ?? _newReportId();
    final payload = _transportPayload(reportId, report);
    return _sendPayload(reportId, payload, queueOnFailure: true);
  }

  String _transportPayload(String reportId, Map<String, Object?> report) {
    final inline = jsonEncode(report);
    final inlineBytes = utf8.encode(inline);
    if (inlineBytes.length <= inlinePayloadThresholdBytes) return inline;

    final compressed = gzip.encode(inlineBytes);
    final activeScript = report['activeScript'];
    return jsonEncode({
      'schemaVersion': report['schemaVersion'],
      'reportId': reportId,
      'deviceKey': report['deviceKey'],
      'consentVersion': report['consentVersion'],
      'appVersion': report['appVersion'],
      'platform': report['platform'],
      'createdAt': report['createdAt'],
      'userText': report['userText'],
      'activeScript': _activeScriptSummary(activeScript),
      'diagnostics': _diagnosticSummary(report['diagnostics']),
      'transport': {
        'mode': 'compressedFullReport',
        'encoding': 'gzip+base64',
        'fileName': '$reportId.full-report.json.gz',
        'originalJsonBytes': inlineBytes.length,
        'compressedBytes': compressed.length,
        'fullReportGzipBase64': base64Encode(compressed),
      },
    });
  }

  Object? _activeScriptSummary(Object? activeScript) {
    if (activeScript is! Map) return activeScript;
    final rawText = activeScript['rawText']?.toString() ?? '';
    return {
      'title': activeScript['title'],
      'sourceType': activeScript['sourceType'],
      'sessionId': activeScript['sessionId'],
      'isRtl': activeScript['isRtl'],
      'wordCount': activeScript['wordCount'],
      'rawTextAttachedInCompressedReport': true,
      'rawTextBytes': utf8.encode(rawText).length,
    };
  }

  Object? _diagnosticSummary(Object? diagnostics) {
    if (diagnostics is! Map) return diagnostics;
    return {
      'teleprompter': diagnostics['teleprompter'],
      'settings': diagnostics['settings'],
      'ringBufferAttachedInCompressedReport': true,
    };
  }

  Future<FeedbackSendResult> _sendPayload(
    String reportId,
    String payload, {
    required bool queueOnFailure,
  }) async {
    if (_accountBackendConfig.isConfigured) {
      try {
        await _accountBackendService
            .submitFeedbackPayload(payload)
            .timeout(requestTimeout);
        return FeedbackSendResult(
          sent: true,
          queued: false,
          reportId: reportId,
          message: 'Feedback sent. Report ID: $reportId',
        );
      } catch (error) {
        if (queueOnFailure) await _queueReport(reportId, payload);
        final failureClass = _transportFailureClass(error);
        _recordFailure(failureClass, reportId, {
          'errorType': error.runtimeType.toString(),
          'error': error.toString(),
          'transport': 'accountBackend',
        });
        return FeedbackSendResult(
          sent: false,
          queued: queueOnFailure,
          reportId: reportId,
          failureClass: failureClass,
          message: 'Could not send feedback through the account backend.'
              '${queueOnFailure ? " Report saved locally." : ""}',
        );
      }
    }

    if (_endpoint.trim().isEmpty) {
      if (queueOnFailure) await _queueReport(reportId, payload);
      return FeedbackSendResult(
        sent: false,
        queued: queueOnFailure,
        reportId: reportId,
        failureClass: 'endpointMissing',
        message: queueOnFailure
            ? 'Feedback service is not configured. Report saved locally.'
            : 'Feedback service is not configured yet.',
      );
    }

    try {
      final uri = _feedbackUri(_endpoint);
      if (!_isAllowedFeedbackUri(uri)) {
        if (queueOnFailure) await _queueReport(reportId, payload);
        _recordFailure('endpointRejected', reportId,
            {'scheme': uri.scheme, 'host': uri.host});
        return FeedbackSendResult(
          sent: false,
          queued: queueOnFailure,
          reportId: reportId,
          failureClass: 'endpointRejected',
          message: 'Feedback service endpoint must use HTTPS.'
              '${queueOnFailure ? " Report saved locally." : ""}',
        );
      }
      final bytes = utf8.encode(payload);
      final response = await _sendWithRedirects(
        uri: uri,
        reportId: reportId,
        body: bytes,
        gzipped: false,
      ).timeout(requestTimeout);
      if (response.isAccepted) {
        return FeedbackSendResult(
          sent: true,
          queued: false,
          reportId: reportId,
          message: response.body.trim().isEmpty
              ? 'Feedback sent. Report ID: $reportId'
              : 'Feedback sent. Report ID: $reportId',
        );
      }
      if (queueOnFailure) await _queueReport(reportId, payload);
      final serverMessage = response.serverMessage;
      _recordFailure('serverRejected', reportId, {
        'statusCode': response.statusCode,
        if (serverMessage != null) 'serverMessage': serverMessage,
      });
      return FeedbackSendResult(
        sent: false,
        queued: queueOnFailure,
        reportId: reportId,
        failureClass: 'serverRejected',
        message: (serverMessage == null
                ? 'Server returned ${response.statusCode}.'
                : 'Feedback service rejected the report: $serverMessage.') +
            (queueOnFailure ? ' Report saved locally.' : ''),
      );
    } catch (error) {
      if (queueOnFailure) await _queueReport(reportId, payload);
      final failureClass = _transportFailureClass(error);
      _recordFailure(failureClass, reportId, {
        'errorType': error.runtimeType.toString(),
        'error': error.toString(),
      });
      return FeedbackSendResult(
        sent: false,
        queued: queueOnFailure,
        reportId: reportId,
        failureClass: failureClass,
        message: 'Could not send feedback.'
            '${queueOnFailure ? " Report saved locally." : ""}',
      );
    }
  }

  bool _isAllowedFeedbackUri(Uri uri) {
    if (uri.scheme == 'https') return true;
    if (uri.scheme != 'http') return false;
    final host = uri.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  String _transportFailureClass(Object error) {
    if (error is TimeoutException) return 'timeout';
    if (error is HandshakeException) return 'tlsHandshake';
    if (error is SocketException) return 'networkSocket';
    if (error is HttpException) return 'httpTransport';
    if (error is FormatException) return 'badEndpointFormat';
    return 'transportError';
  }

  void _recordFailure(
    String failureClass,
    String reportId,
    Map<String, Object?> data,
  ) {
    LightweightDiagnostics.instance.record(
      'feedback',
      'feedback $failureClass',
      data: {'reportId': reportId, ...data},
    );
  }

  Future<_FeedbackHttpResponse> _sendWithRedirects({
    required Uri uri,
    required String reportId,
    required List<int> body,
    required bool gzipped,
  }) async {
    var current = uri;
    var method = 'POST';
    for (var i = 0; i <= maxRedirects; i++) {
      final request = method == 'POST'
          ? await _client.postUrl(current)
          : await _client.getUrl(current);
      request.followRedirects = false;
      request.headers.set('X-AutoTeleprompter-Report-Id', reportId);
      if (method == 'POST') {
        request.headers.contentType = ContentType.json;
        if (gzipped) {
          request.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
        }
        request.add(body);
      }
      final response = await request.close();
      if (!_isRedirect(response.statusCode)) {
        final text = await response.transform(utf8.decoder).join();
        return _FeedbackHttpResponse(response.statusCode, text);
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null || location.trim().isEmpty) {
        return _FeedbackHttpResponse(response.statusCode, '');
      }
      current = current.resolve(location);
      method = _preservePostOnRedirect(response.statusCode) ? method : 'GET';
    }
    return const _FeedbackHttpResponse(310, 'Too many redirects.');
  }

  bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;

  bool _preservePostOnRedirect(int statusCode) =>
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;

  Future<int> pendingReportCount() async {
    final dir = await _ensureOutboxDirectory();
    return _pendingFiles(dir).length;
  }

  Future<int> deletePendingReports() async {
    final dir = await _ensureOutboxDirectory();
    final files = _pendingFiles(dir);
    var deleted = 0;
    for (final file in files) {
      try {
        await file.delete();
        deleted++;
      } catch (_) {}
    }
    return deleted;
  }

  Future<FeedbackOutboxRetryResult> retryPendingReports() async {
    final dir = await _ensureOutboxDirectory();
    final files = _pendingFiles(dir);
    var sent = 0;
    String? lastFailureClass;
    String? lastFailureMessage;
    for (final file in files) {
      try {
        final payload = await _readPendingPayload(file);
        final reportId = _reportIdFromFile(file);
        final result = await _sendPayload(
          reportId,
          payload,
          queueOnFailure: false,
        );
        if (result.sent) {
          await file.delete();
          sent++;
        } else {
          lastFailureClass = result.failureClass;
          lastFailureMessage = result.message;
        }
      } catch (error) {
        lastFailureClass = 'retryReadOrSendFailed';
        lastFailureMessage = error.toString();
        _recordFailure('retryReadOrSendFailed', _reportIdFromFile(file),
            {'error': error.toString()});
      }
    }
    final remaining = await pendingReportCount();
    final failure = lastFailureMessage;
    final failureSuffix = failure == null
        ? ''
        : ' Last failure: ${_compactFailureMessage(failure)}';
    return FeedbackOutboxRetryResult(
      sent: sent,
      remaining: remaining,
      message: sent == 0
          ? 'No pending reports were sent. $remaining still saved locally.'
              '$failureSuffix'
          : 'Sent $sent pending report(s). $remaining still saved locally.'
              '$failureSuffix',
    );
  }

  String _compactFailureMessage(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 180) return compact;
    return '${compact.substring(0, 177)}...';
  }

  Future<void> _queueReport(String reportId, String payload) async {
    final dir = await _ensureOutboxDirectory();
    final safeReportId = _safeReportId(reportId);
    final file = File(
      '${dir.path}${Platform.pathSeparator}$safeReportId.json.gz.atpe',
    );
    final encrypted = await _encryptedStore.protectToEnvelopeAsync(
      gzip.encode(utf8.encode(payload)),
      kind: 'feedback-report',
      compress: false,
    );
    await file.writeAsString(encrypted, flush: true);
    await _enforceOutboxLimit(dir);
  }

  String _safeReportId(String reportId) {
    final safe = reportId
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^[_\.-]+|[_\.-]+$'), '');
    if (safe.isEmpty) return _newReportId();
    return safe.length > 90 ? safe.substring(0, 90) : safe;
  }

  Future<void> _enforceOutboxLimit(Directory dir) async {
    final files = _pendingFiles(dir)
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final file in files.skip(maxPendingReports)) {
      try {
        await file.delete();
      } catch (error) {
        _recordFailure('outboxLimitDeleteFailed', _reportIdFromFile(file), {
          'error': error.toString(),
        });
      }
    }
  }

  Future<Directory> _ensureOutboxDirectory() async {
    final outboxDirectory = _outboxDirectory;
    final base = outboxDirectory == null
        ? await getApplicationSupportDirectory()
        : await outboxDirectory();
    final dir =
        Directory('${base.path}${Platform.pathSeparator}feedback_outbox');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await _migrateLegacyOutbox(dir);
    return dir;
  }

  Future<void> _migrateLegacyOutbox(Directory dir) async {
    final legacyFiles = dir
        .listSync()
        .whereType<File>()
        .where((file) =>
            file.path.endsWith('.json.gz') && !file.path.endsWith('.atpe'))
        .toList();
    for (final file in legacyFiles) {
      try {
        final encrypted = await _encryptedStore.protectToEnvelopeAsync(
          await file.readAsBytes(),
          kind: 'feedback-report',
          compress: false,
        );
        await File('${file.path}.atpe').writeAsString(encrypted, flush: true);
        await file.delete();
      } catch (_) {}
    }
  }

  Uri _feedbackUri(String endpoint) {
    final uri = Uri.parse(endpoint);
    if (uri.path.isEmpty || uri.path == '/') {
      return uri.replace(path: '/v1/feedback');
    }
    return uri;
  }

  List<File> _pendingFiles(Directory dir) => dir
      .listSync()
      .whereType<File>()
      .where((file) =>
          file.path.endsWith('.json.gz.atpe') || file.path.endsWith('.json.gz'))
      .toList();

  Future<String> _readPendingPayload(File file) async {
    if (file.path.endsWith('.atpe')) {
      final bytes = await _encryptedStore.readBytes(
        file,
        kind: 'feedback-report',
      );
      return utf8.decode(gzip.decode(bytes));
    }
    return utf8.decode(gzip.decode(await file.readAsBytes()));
  }

  String _reportIdFromFile(File file) {
    final name = file.path.split(Platform.pathSeparator).last;
    return name.replaceFirst(RegExp(r'\.json\.gz(?:\.atpe)?$'), '');
  }

  String _newReportId() =>
      'rpt_${DateTime.now().toUtc().millisecondsSinceEpoch}';
}

class _FeedbackHttpResponse {
  final int statusCode;
  final String body;

  const _FeedbackHttpResponse(this.statusCode, this.body);

  bool get isOk => statusCode >= 200 && statusCode < 300;

  bool get isAccepted {
    if (!isOk) return false;
    final trimmed = body.trim();
    if (trimmed.isEmpty) return false;
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map && decoded['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  String? get serverMessage {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final error = decoded['error'] ?? decoded['message'];
        if (error != null) return error.toString();
      }
    } catch (_) {}
    if (isOk) return 'unexpected response from feedback inbox';
    return null;
  }
}
