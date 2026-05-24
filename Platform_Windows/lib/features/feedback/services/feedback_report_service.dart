import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

const feedbackEndpoint = String.fromEnvironment('FEEDBACK_ENDPOINT');

class FeedbackSendResult {
  final bool sent;
  final bool queued;
  final String reportId;
  final String message;

  const FeedbackSendResult({
    required this.sent,
    required this.queued,
    required this.reportId,
    required this.message,
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
  static const int gzipThresholdBytes = 64 * 1024;
  static const int maxPendingReports = 3;

  FeedbackReportService({
    HttpClient? client,
    Future<Directory> Function()? outboxDirectory,
    String endpoint = feedbackEndpoint,
  })  : _client = client ?? HttpClient(),
        _outboxDirectory = outboxDirectory,
        _endpoint = endpoint;

  final HttpClient _client;
  final Future<Directory> Function()? _outboxDirectory;
  final String _endpoint;

  Future<FeedbackSendResult> submit(Map<String, Object?> report) async {
    final reportId = report['reportId']?.toString() ?? _newReportId();
    final payload = jsonEncode(report);
    return _sendPayload(reportId, payload, queueOnFailure: true);
  }

  Future<FeedbackSendResult> _sendPayload(
    String reportId,
    String payload, {
    required bool queueOnFailure,
  }) async {
    if (_endpoint.trim().isEmpty) {
      if (queueOnFailure) await _queueReport(reportId, payload);
      return FeedbackSendResult(
        sent: false,
        queued: queueOnFailure,
        reportId: reportId,
        message: queueOnFailure
            ? 'Feedback service is not configured. Report saved locally.'
            : 'Feedback service is not configured yet.',
      );
    }

    try {
      final uri = _feedbackUri(_endpoint);
      final bytes = utf8.encode(payload);
      final body =
          bytes.length > gzipThresholdBytes ? gzip.encode(bytes) : bytes;
      final request = await _client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set('X-AutoTeleprompter-Report-Id', reportId);
      if (!identical(body, bytes)) {
        request.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      }
      request.add(body);
      final response = await request.close();
      final responseText = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return FeedbackSendResult(
          sent: true,
          queued: false,
          reportId: reportId,
          message: responseText.trim().isEmpty
              ? 'Feedback sent. Report ID: $reportId'
              : 'Feedback sent. Report ID: $reportId',
        );
      }
      if (queueOnFailure) await _queueReport(reportId, payload);
      return FeedbackSendResult(
        sent: false,
        queued: queueOnFailure,
        reportId: reportId,
        message: 'Server returned ${response.statusCode}.'
            '${queueOnFailure ? ' Report saved locally.' : ''}',
      );
    } catch (error) {
      if (queueOnFailure) await _queueReport(reportId, payload);
      return FeedbackSendResult(
        sent: false,
        queued: queueOnFailure,
        reportId: reportId,
        message: 'Could not send feedback.'
            '${queueOnFailure ? ' Report saved locally.' : ''}',
      );
    }
  }

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
    for (final file in files) {
      try {
        final payload = utf8.decode(gzip.decode(await file.readAsBytes()));
        final reportId = _reportIdFromFile(file);
        final result = await _sendPayload(
          reportId,
          payload,
          queueOnFailure: false,
        );
        if (result.sent) {
          await file.delete();
          sent++;
        }
      } catch (_) {}
    }
    final remaining = await pendingReportCount();
    return FeedbackOutboxRetryResult(
      sent: sent,
      remaining: remaining,
      message: sent == 0
          ? 'No pending reports were sent. $remaining still saved locally.'
          : 'Sent $sent pending report(s). $remaining still saved locally.',
    );
  }

  Future<void> _queueReport(String reportId, String payload) async {
    final dir = await _ensureOutboxDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$reportId.json.gz');
    await file.writeAsBytes(gzip.encode(utf8.encode(payload)), flush: true);
    await _enforceOutboxLimit(dir);
  }

  Future<void> _enforceOutboxLimit(Directory dir) async {
    final files = _pendingFiles(dir)
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final file in files.skip(maxPendingReports)) {
      try {
        await file.delete();
      } catch (_) {}
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
    return dir;
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
      .where((file) => file.path.endsWith('.json.gz'))
      .toList();

  String _reportIdFromFile(File file) {
    final name = file.path.split(Platform.pathSeparator).last;
    return name.replaceFirst(RegExp(r'\.json\.gz$'), '');
  }

  String _newReportId() =>
      'rpt_${DateTime.now().toUtc().millisecondsSinceEpoch}';
}
