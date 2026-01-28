// Web implementation: in-app resume viewer using an iframe via HtmlElementView
import 'dart:html' as html;
import 'dart:ui_web' as ui_web; // IMPORT ADDED: Required for platformViewRegistry in new Flutter versions
import 'package:flutter/material.dart';

class ResumeViewerPage extends StatelessWidget {
  final String resumeUrl;
  ResumeViewerPage({Key? key, required this.resumeUrl}) : super(key: key) {
    final viewId = 'resume-viewer-${resumeUrl.hashCode}';
    try {
      // Register an iframe view for this resume URL
      // UPDATED: Use 'ui_web' instead of 'ui'
      ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewIdInt) {
        final iframe = html.IFrameElement()
          ..style.border = 'none'
          ..src = resumeUrl
          ..width = '100%'
          ..height = '100%';
        return iframe;
      });
    } catch (_) {
      // registration may fail in hot-reload/dev; fall back to external open when needed
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewId = 'resume-viewer-${resumeUrl.hashCode}';
    return Scaffold(
      appBar: AppBar(title: const Text('Resume Preview')),
      body: SizedBox.expand(
        child: HtmlElementView(viewType: viewId),
      ),
    );
  }
}