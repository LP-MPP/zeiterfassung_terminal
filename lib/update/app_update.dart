class AppUpdate {
  const AppUpdate({
    required this.versionCode,
    required this.versionName,
    required this.apkUri,
    required this.sha256,
    required this.releaseNotes,
    required this.mandatory,
    this.apkSize,
  });

  final int versionCode;
  final String versionName;
  final Uri apkUri;
  final String sha256;
  final String releaseNotes;
  final bool mandatory;
  final int? apkSize;

  factory AppUpdate.fromJson(Map<String, dynamic> json) {
    final versionCode = (json['versionCode'] as num?)?.toInt();
    final versionName = (json['versionName'] as String?)?.trim() ?? '';
    final apkUrl = (json['apkUrl'] as String?)?.trim() ?? '';
    final checksum = (json['sha256'] as String?)?.trim().toLowerCase() ?? '';
    final apkUri = Uri.tryParse(apkUrl);

    if (versionCode == null || versionCode <= 0) {
      throw const FormatException('Ungültiger versionCode im Update-Manifest.');
    }
    if (versionName.isEmpty) {
      throw const FormatException('Fehlender versionName im Update-Manifest.');
    }
    if (apkUri == null || apkUri.scheme != 'https' || apkUri.host.isEmpty) {
      throw const FormatException(
        'Die APK-Adresse muss eine HTTPS-Adresse sein.',
      );
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum)) {
      throw const FormatException('Ungültige SHA-256-Prüfsumme.');
    }

    final size = (json['apkSize'] as num?)?.toInt();
    if (size != null && size <= 0) {
      throw const FormatException('Ungültige APK-Größe.');
    }

    return AppUpdate(
      versionCode: versionCode,
      versionName: versionName,
      apkUri: apkUri,
      sha256: checksum,
      releaseNotes: (json['releaseNotes'] as String?)?.trim() ?? '',
      mandatory: json['mandatory'] == true,
      apkSize: size,
    );
  }
}
