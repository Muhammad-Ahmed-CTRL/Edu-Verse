// Web implementation to trigger automatic download for a data URL or URL
import 'dart:html' as html;

Future<void> triggerDownload(String url,
    {String filename = 'resume.pdf'}) async {
  try {
    final anchor = html.AnchorElement(href: url)
      ..target = '_blank'
      ..download = filename;
    html.document.body!.append(anchor);
    anchor.click();
    anchor.remove();
  } catch (e) {
    // ignore — fallback will be used by caller
  }
}
