import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ml_service.dart';

/// Connection and workflow service for Laptop-Assisted Training.
///
/// Communicates over HTTP (LAN or USB ADB reverse) with the local
/// Python training service (`backend/training_service.py`).
class LaptopTrainingService {
  final MlService _ml;
  final SharedPreferences? _prefs;

  static const String _hostPrefKey = 'laptop_training_service_host';
  static const String defaultHost = 'http://10.0.2.2:8000'; // Default for Android emulator

  LaptopTrainingService({
    required MlService ml,
    SharedPreferences? prefs,
  })  : _ml = ml,
        _prefs = prefs;

  String get configuredHost {
    return _prefs?.getString(_hostPrefKey) ?? defaultHost;
  }

  Future<void> setConfiguredHost(String host) async {
    final cleanHost = host.trim().replaceAll(RegExp(r'/+$'), '');
    await _prefs?.setString(_hostPrefKey, cleanHost);
  }

  /// Check connectivity and health of the laptop training service.
  Future<bool> checkHealth({String? overrideHost, Duration timeout = const Duration(seconds: 3)}) async {
    final baseUrl = overrideHost ?? configuredHost;
    final uri = Uri.parse('$baseUrl/health');

    final client = HttpClient();
    client.connectionTimeout = timeout;

    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);

      if (response.statusCode == HttpStatus.ok) {
        final body = await response.transform(utf8.decoder).join();
        final map = jsonDecode(body);
        return map['status'] == 'ok';
      }
      return false;
    } catch (e) {
      debugPrint('LaptopTraining: Health check failed for $uri: $e');
      return false;
    } finally {
      client.close();
    }
  }

  /// Upload an exported session CSV file to the laptop training service.
  Future<String> uploadSessionCsv({
    required String csvPath,
    String? overrideHost,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final file = File(csvPath);
    if (!await file.exists()) {
      throw FileSystemException('CSV file does not exist', csvPath);
    }

    final baseUrl = overrideHost ?? configuredHost;
    final uri = Uri.parse('$baseUrl/upload-dataset');
    final boundary = '----BandanaBoundary${DateTime.now().millisecondsSinceEpoch}';

    final client = HttpClient();
    client.connectionTimeout = timeout;

    try {
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');

      final fileName = file.uri.pathSegments.last;
      final fileBytes = await file.readAsBytes();

      final header = '--$boundary\r\n'
          'Content-Disposition: form-data; name="file"; filename="$fileName"\r\n'
          'Content-Type: text/csv\r\n\r\n';
      final footer = '\r\n--$boundary--\r\n';

      final headerBytes = utf8.encode(header);
      final footerBytes = utf8.encode(footer);

      request.contentLength = headerBytes.length + fileBytes.length + footerBytes.length;
      request.add(headerBytes);
      request.add(fileBytes);
      request.add(footerBytes);

      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == HttpStatus.ok) {
        final map = jsonDecode(body);
        return map['dataset_id'] as String;
      } else {
        throw HttpException('Upload failed with status ${response.statusCode}: $body', uri: uri);
      }
    } finally {
      client.close();
    }
  }

  /// Request model training on the laptop.
  Future<Map<String, dynamic>> requestTraining({
    required String datasetId,
    required String algorithm,
    required int featureLength,
    String? overrideHost,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final baseUrl = overrideHost ?? configuredHost;
    final uri = Uri.parse('$baseUrl/train');

    final client = HttpClient();
    client.connectionTimeout = timeout;

    try {
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;

      final payload = jsonEncode({
        'dataset_id': datasetId,
        'algorithm': algorithm,
        'feature_length': featureLength,
        'test_session_ratio': 0.25,
      });

      request.write(payload);
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == HttpStatus.ok) {
        return jsonDecode(body) as Map<String, dynamic>;
      } else {
        throw HttpException('Training request failed: $body', uri: uri);
      }
    } finally {
      client.close();
    }
  }

  /// Download and activate a trained JSON model artifact from the laptop.
  Future<bool> downloadAndActivateModel({
    required String modelId,
    required bool combined,
    String? overrideHost,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final baseUrl = overrideHost ?? configuredHost;
    final uri = Uri.parse('$baseUrl/model-artifact/$modelId');

    final client = HttpClient();
    client.connectionTimeout = timeout;

    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);

      if (response.statusCode == HttpStatus.ok) {
        final jsonStr = await response.transform(utf8.decoder).join();
        return await _ml.importModelJson(jsonStr, combined: combined);
      }
      return false;
    } catch (e) {
      debugPrint('LaptopTraining: Failed to download model artifact: $e');
      return false;
    } finally {
      client.close();
    }
  }
}
