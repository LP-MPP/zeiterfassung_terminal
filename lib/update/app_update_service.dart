import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'app_update.dart';

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppUpdateService {
  AppUpdateService({HttpClient? httpClient, Uri? manifestUri})
    : _httpClient = httpClient ?? HttpClient(),
      manifestUri =
          manifestUri ??
          Uri.parse('https://zeiterfassung-ebafa.web.app/updates/update.json');

  static const MethodChannel _channel = MethodChannel(
    'de.mpp.zeiterfassung/updates',
  );

  final HttpClient _httpClient;
  final Uri manifestUri;

  Future<AppUpdate?> checkForUpdate() async {
    try {
      final version = await _channel.invokeMapMethod<String, dynamic>(
        'getVersionInfo',
      );
      final installedVersionCode = (version?['versionCode'] as num?)?.toInt();
      if (installedVersionCode == null) {
        throw const AppUpdateException(
          'Installierte App-Version konnte nicht ermittelt werden.',
        );
      }

      final request = await _httpClient
          .getUrl(manifestUri)
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw AppUpdateException(
          'Update-Prüfung fehlgeschlagen (HTTP ${response.statusCode}).',
        );
      }

      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const AppUpdateException('Ungültiges Update-Manifest.');
      }

      final update = AppUpdate.fromJson(decoded);
      return update.versionCode > installedVersionCode ? update : null;
    } on AppUpdateException {
      rethrow;
    } on FormatException catch (error) {
      throw AppUpdateException(error.message);
    } on PlatformException catch (error) {
      throw AppUpdateException(
        error.message ?? 'Android-Version konnte nicht geprüft werden.',
      );
    } catch (_) {
      throw const AppUpdateException(
        'Update-Prüfung derzeit nicht möglich. Bitte Internetverbindung prüfen.',
      );
    }
  }

  Future<bool> canInstallPackages() async =>
      await _channel.invokeMethod<bool>('canInstallPackages') ?? false;

  Future<void> openInstallPermissionSettings() async {
    await _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  Future<void> downloadAndInstall(
    AppUpdate update, {
    required void Function(double progress) onProgress,
  }) async {
    final updateDirectory = Directory('${Directory.systemTemp.path}/updates');
    await updateDirectory.create(recursive: true);
    final apk = File('${updateDirectory.path}/zeiterfassung-terminal.apk');
    final partial = File('${apk.path}.download');

    if (await partial.exists()) await partial.delete();

    try {
      final request = await _httpClient
          .getUrl(update.apkUri)
          .timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw AppUpdateException(
          'Download fehlgeschlagen (HTTP ${response.statusCode}).',
        );
      }

      final expectedBytes = update.apkSize ?? response.contentLength;
      var receivedBytes = 0;
      final sink = partial.openWrite();
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (expectedBytes > 0) {
            onProgress((receivedBytes / expectedBytes).clamp(0, 1));
          }
        }
      } finally {
        await sink.close();
      }

      if (update.apkSize != null && receivedBytes != update.apkSize) {
        throw const AppUpdateException(
          'Der Download ist unvollständig. Bitte erneut versuchen.',
        );
      }

      final digest = await sha256.bind(partial.openRead()).first;
      if (digest.toString().toLowerCase() != update.sha256) {
        throw const AppUpdateException(
          'Sicherheitsprüfung fehlgeschlagen. Die APK wurde nicht installiert.',
        );
      }

      if (await apk.exists()) await apk.delete();
      await partial.rename(apk.path);
      onProgress(1);
      await _channel.invokeMethod<void>('installApk', {'path': apk.path});
    } on AppUpdateException {
      rethrow;
    } on PlatformException catch (error) {
      throw AppUpdateException(
        error.message ?? 'Android-Installation konnte nicht gestartet werden.',
      );
    } catch (_) {
      throw const AppUpdateException(
        'Update konnte nicht geladen werden. Bitte erneut versuchen.',
      );
    } finally {
      if (await partial.exists()) await partial.delete();
    }
  }

  void close() => _httpClient.close(force: true);
}
