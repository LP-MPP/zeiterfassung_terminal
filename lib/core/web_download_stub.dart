import 'dart:typed_data';

/// Non-web fallback: no-op (or could use share_plus in a real mobile build).
void downloadBytes({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) {
  // On non-web platforms this is a no-op.
  // The admin panel is web-only, so this stub is rarely reached.
}
