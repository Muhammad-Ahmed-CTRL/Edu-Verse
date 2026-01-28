// Conditional export for resume viewer: use stub by default, web implementation when available
export 'resume_viewer_stub.dart'
    if (dart.library.html) 'resume_viewer_web.dart';
