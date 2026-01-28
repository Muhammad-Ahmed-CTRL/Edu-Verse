// Conditional export for web download helper: stub by default, web impl on web
export 'web_download_stub.dart' if (dart.library.html) 'web_download_web.dart';
