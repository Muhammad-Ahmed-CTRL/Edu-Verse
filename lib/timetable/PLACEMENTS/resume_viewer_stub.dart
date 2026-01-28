import 'dart:convert'; // For base64Decode
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class ResumeViewerPage extends StatelessWidget {
  final String resumeUrl;
  const ResumeViewerPage({Key? key, required this.resumeUrl}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resume Preview'),
        backgroundColor: const Color(0xFF5E2686),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      // Switch between Memory (Base64) and Network (URL) view
      body: _isBase64(resumeUrl) 
          ? _buildBase64Viewer(context, resumeUrl) 
          : _buildNetworkViewer(context, resumeUrl),
    );
  }

  /// Helper to check if the string is likely Base64 data
  bool _isBase64(String str) {
    return str.startsWith('data:application/pdf;base64,') || 
           (str.length > 500 && !str.startsWith('http'));
  }

  /// Viewer for Base64 Data
  Widget _buildBase64Viewer(BuildContext context, String data) {
    try {
      // 1. Clean the string (remove the data URI prefix if present)
      String cleanBase64 = data;
      if (data.startsWith('data:application/pdf;base64,')) {
        cleanBase64 = data.substring('data:application/pdf;base64,'.length);
      }

      // 2. Decode to bytes
      final Uint8List bytes = base64Decode(cleanBase64);

      // 3. Show PDF from Memory
      return SfPdfViewer.memory(
        bytes,
        canShowScrollHead: false,
        onDocumentLoadFailed: (details) {
          _showError(context, "Failed to render PDF: ${details.description}");
        },
      );
    } catch (e) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text("Error decoding resume data.\n$e", textAlign: TextAlign.center),
        ),
      );
    }
  }

  /// Viewer for Standard URLs (Firebase/Http)
  Widget _buildNetworkViewer(BuildContext context, String url) {
    return SfPdfViewer.network(
      url,
      canShowScrollHead: false,
      onDocumentLoadFailed: (details) {
        _showError(context, "Failed to load PDF from network.\n${details.description}");
      },
    );
  }

  void _showError(BuildContext context, String message) {
    // Delay error snackbar to avoid build conflicts
    Future.microtask(() {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });
  }
}