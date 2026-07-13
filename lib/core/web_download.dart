// Conditional import: picks the right implementation at compile time.
// On web → web_download_web.dart (uses dart:html)
// Elsewhere → web_download_stub.dart (uses share_plus)
export 'web_download_stub.dart' if (dart.library.html) 'web_download_web.dart';
