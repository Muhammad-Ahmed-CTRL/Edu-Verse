// pubspec.yaml dependencies needed:
// flutter_svg: ^2.0.9
// google_fonts: ^6.1.0
// provider: ^6.1.1
// http: ^1.1.0
// fl_chart: ^0.65.0
// firebase_core: ^2.24.2
// cloud_firestore: ^4.13.6
// firebase_auth: ^4.15.3
// flutter_dotenv: ^5.1.0  <-- Make sure this is added

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Added for .env support
import 'package:reclaimify/theme_colors.dart';
// ============================================================================
// CONSTANTS
// ============================================================================
// Prefer API key from compile-time environment `GROQ_API_KEY` (use --dart-define)
// Do NOT ship a hardcoded key. Default to empty so missing configuration
// is explicit and the app can guide the developer/user to configure a valid key.
const String groqApiKey = String.fromEnvironment('GROQ_API_KEY', defaultValue: '');

// Note: Colors are now imported from 'package:reclaimify/theme_colors.dart'
// to ensure consistency across the app (Dark/Light mode support).

// This file is a module (widget set) intended to be embedded inside the
// main app. It no longer defines its own `main()` or `MaterialApp` to avoid
// duplicate app initialisation when imported. Use `StudyPlannerModule` to
// wrap the planner with required providers and expose `StudyPlannerPage`.

// Simple Task model
class Task {
  String? id;
  String title;
  bool isCompleted;
  int durationSeconds;

  Task({this.id, required this.title, this.isCompleted = false, this.durationSeconds = 1500});
}

class StudyPlannerModule extends StatelessWidget {
  const StudyPlannerModule({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => StudyDataProvider()),
      ],
      child: const StudyPlannerPage(),
    );
  }
}

// ============================================================================
// GROQ API SERVICE
// ============================================================================
class GroqService {
  static const String _endpoint = 'https://api.groq.com/openai/v1/chat/completions';
  // Use a stable Llama 3.1 instant model as the default; provide a
  // long-context model when the message suggests large context requests.
  static const String _defaultModel = 'llama-3.1-8b-instant';
  static const String _longContextModel = 'meta-llama/llama-4-maverick-17b-128e-instruct';

  // Helper to ensure .env is loaded (lazy loading to avoid modifying main.dart)
  static bool _isEnvLoaded = false;
  static Future<void> _ensureEnvLoaded() async {
    if (_isEnvLoaded) return;
    try {
      await dotenv.load(fileName: ".env");
      _isEnvLoaded = true;
    } catch (e) {
      debugPrint("GroqService: Failed to load .env file: $e");
      // Mark as loaded to prevent retry loops on failure
      _isEnvLoaded = true; 
    }
  }

  // Resolve API key from multiple sources. Prefers (highest->lowest):
  // 1. explicit `apiKey` param
  // 2. .env file (GROQ_API_KEY)
  // 3. SharedPreferences runtime value (saved via settings)
  // 4. compile-time `GROQ_API_KEY` (--dart-define)
  // 5. assets/groq_config.json
  static Future<Map<String, String>> _resolveApiKey(String? param) async {
    String key = '';
    String source = 'none';
    if (param != null && param.isNotEmpty) {
      return {'key': param.trim(), 'source': 'param'};
    }

    // Attempt to load from .env
    await _ensureEnvLoaded();
    final envKey = dotenv.env['GROQ_API_KEY'];
    if (envKey != null && envKey.isNotEmpty) {
      return {'key': envKey.trim(), 'source': '.env'};
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('GROQ_API_KEY') ?? '';
      if (saved.isNotEmpty) return {'key': saved.trim(), 'source': 'preferences'};
    } catch (_) {}

    if (groqApiKey.isNotEmpty) return {'key': groqApiKey, 'source': 'compile_define'};

    try {
      final raw = await rootBundle.loadString('assets/groq_config.json');
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final assetKey = (parsed['GROQ_API_KEY']?.toString() ?? '').trim();
      if (assetKey.isNotEmpty) return {'key': assetKey, 'source': 'asset'};
    } catch (_) {}

    return {'key': '', 'source': 'none'};
  }

  /// Send a chat completion request to Groq. `apiKey` is optional and will
  /// default to the .env key or compile-time `groqApiKey` if not provided.
  static Future<String> sendMessage({
    String? apiKey,
    required String userMessage,
    List<Map<String, String>>? conversationHistory,
    String? model,
    double temperature = 0.1,
    int maxTokens = 400,
  }) async {
    try {
      final messages = [
        {
          'role': 'system',
          'content': 'You are a helpful AI study assistant. Provide concise, encouraging advice for students. Keep responses brief and actionable.'
        },
        if (conversationHistory != null) ...conversationHistory,
        {'role': 'user', 'content': userMessage},
      ];

      final usedModel = model ?? _selectModelForMessage(userMessage);

      // Resolve API key using unified helper
      final resolved = await _resolveApiKey(apiKey);
      final String keyToUse = resolved['key'] ?? '';
      final String keySource = resolved['source'] ?? 'none';

      debugPrint('GroqService: API key present=${keyToUse.isNotEmpty}; source=$keySource');

      if (keyToUse.isEmpty) {
        debugPrint('GroqService warning: no GROQ API key provided; requests will be skipped.');
        return 'AI not configured: please provide a valid GROQ API key in settings or .env file.';
      }

      final request = http.post(
        Uri.parse(_endpoint),
        headers: {
          'Authorization': 'Bearer $keyToUse',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': usedModel,
          'messages': messages,
          'temperature': temperature,
          'max_tokens': maxTokens,
        }),
      );

      // Debug: log the outgoing payload shape and truncated body, but never
      // print the API key.
      try {
        final Map<String, dynamic> outBody = {
          'model': usedModel,
          'messages_count': messages.length,
          'temperature': temperature,
          'max_tokens': maxTokens,
        };
        debugPrint('GroqService outgoing payload shape: ${jsonEncode(outBody)}');
      } catch (_) {}

      // enforce a timeout so the UI doesn't stay stuck indefinitely
      final response = await request.timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        try {
          return data['choices'][0]['message']['content']?.toString() ?? '';
        } catch (_) {
          return '';
        }
      } else {
        // Log the non-200 response body to help diagnose payload/validation issues.
        try {
          debugPrint('GroqService non-200 response: ${response.statusCode}');
          debugPrint('GroqService response body (truncated): ${response.body.length > 1000 ? response.body.substring(0, 1000) + "..." : response.body}');
        } catch (_) {}

        // Attempt to parse error details to detect decommissioned model
        String errorCode = '';
        String errorMsg = '';
        try {
          final parsed = jsonDecode(response.body);
          if (parsed is Map && parsed['error'] is Map) {
            errorCode = parsed['error']['code']?.toString() ?? '';
            errorMsg = parsed['error']['message']?.toString() ?? '';
          } else if (parsed is Map && parsed['message'] != null) {
            errorMsg = parsed['message'].toString();
          }
        } catch (_) {}
        
        // If non-200 or model decommissioned, return local fallback to keep UI responsive.
        if (errorCode == 'model_decommissioned' || response.statusCode != 200) {
          debugPrint('GroqService: returning local fallback due to non-200 or decommissioned model (status=${response.statusCode}, code=$errorCode)');
          try {
            return _localFallback(userMessage);
          } catch (_) {
            return 'Error: ${response.statusCode}${errorMsg.isNotEmpty ? ' - ' + (errorMsg.length > 200 ? errorMsg.substring(0, 200) + '...' : errorMsg) : ''}';
          }
        }

        // Generic error formatting
        return 'Error: ${response.statusCode}${errorMsg.isNotEmpty ? ' - ' + (errorMsg.length > 200 ? errorMsg.substring(0, 200) + '...' : errorMsg) : ''}';
      }
    } catch (e) {
      return 'Error connecting to AI: $e';
    }
  }

  static String _selectModelForMessage(String userMessage) {
    // If user asks for very long context (keywords), prefer long-context model
    final lcTriggers = ['paper', 'multi-file', 'long context', 'whole project', 'full file', 'entire'];
    final low = userMessage.toLowerCase();
    for (final t in lcTriggers) {
      if (low.contains(t)) return _longContextModel;
    }
    return _defaultModel;
  }

  /// Helper: list available models from the Groq API (returns model ids).
  static Future<List<String>> listModels({String? apiKey}) async {
    final resolved = await _resolveApiKey(apiKey);
    final keyToUse = resolved['key'] ?? '';
    final keySource = resolved['source'] ?? 'none';
    debugPrint('GroqService.listModels: API key present=${keyToUse.isNotEmpty}; source=$keySource');
    final uri = Uri.parse('https://api.groq.com/openai/v1/models');
    try {
      final resp = await http.get(uri, headers: {
        'Authorization': 'Bearer $keyToUse',
        'Content-Type': 'application/json',
      }).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return [];
      final parsed = jsonDecode(resp.body);
      if (parsed is Map && parsed['data'] is List) {
        return (parsed['data'] as List).map<String>((e) => e['id']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      }
    } catch (e) {
      debugPrint('GroqService.listModels error: $e');
    }
    return [];
  }

  // Local quick fallback generator for schedule-like requests to keep UI responsive
  static String _localFallback(String userMessage) {
    final m = RegExp(r'for\s+([A-Za-z0-9 &]+)', caseSensitive: false).firstMatch(userMessage);
    final subject = m?.group(1)?.trim() ?? 'your topic';
    // Basic 7-day schedule template
    return '''Day 1 — ${subject}: Read theory (30m), solve basic problems (30m)
Day 2 — ${subject}: Key concepts + worked examples (30m), practice (30m)
Day 3 — ${subject}: Apply concepts to problems (45m), review mistakes (15m)
Day 4 — ${subject}: Mixed practice (60m)
Day 5 — ${subject}: Focus on weak areas (45m), quick revision (15m)
Day 6 — ${subject}: Timed practice (60m)
Day 7 — ${subject}: Mock test + review (90m)

Tips: timebox sessions, focus on problem areas, and review incorrect solutions.''';
  }
}

// ============================================================================
// FIRESTORE SERVICE
// ============================================================================
class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String get userId => FirebaseAuth.instance.currentUser!.uid;

  // Resolve the university id associated with the current user (from profile)
  // Returns null if no university is linked to the user's profile.
  static Future<String?> getUniversityId() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return null;
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      final data = doc.data();
      String? uniId = data?['uniId']?.toString();
      if (uniId == null) {
        final adminScope = data?['adminScope'] as Map<String, dynamic>?;
        if (adminScope != null && adminScope['uniId'] != null) uniId = adminScope['uniId']?.toString();
      }
      return uniId;
    } catch (e) {
      debugPrint('Error resolving university id: $e');
      return null;
    }
  }

  // Save chat message
  static Future<void> saveChatMessage(Map<String, String> message) async {
    try {
      final uniId = await getUniversityId();
      if (uniId != null) {
        // Save under university-scoped AI planner collection, per-user doc
        await _db
            .collection('universities')
            .doc(uniId)
            .collection('ai_planner')
            .doc(userId)
            .collection('chat_history')
            .add({
          ...message,
          'timestamp': FieldValue.serverTimestamp(),
        });
        return;
      }
      // Fallback to per-user collection
      await _db
          .collection('users')
          .doc(userId)
          .collection('chat_history')
          .add({
        ...message,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // On permission-denied or other Firestore errors, persist locally
      // so the UI remains functional. We append the message to
      // SharedPreferences under key `ai_chat_<uid>` as a JSON list.
      try {
        final prefs = await SharedPreferences.getInstance();
        final uniId = await getUniversityId();
        final key = 'ai_chat_${uniId ?? userId}';
        final existing = prefs.getString(key);
        List<Map<String, String>> list = [];
        if (existing != null) {
          try {
            final raw = jsonDecode(existing) as List<dynamic>;
            list = raw.map((e) => Map<String, String>.from(e)).toList();
          } catch (_) {
            list = [];
          }
        }
        list.add({...message, 'timestamp': DateTime.now().toIso8601String()});
        await prefs.setString(key, jsonEncode(list));
      } catch (inner) {
        debugPrint('Failed to persist chat locally: $inner');
      }
      // rethrow the original error so callers can log if desired
      rethrow;
    }
  }

  // Get chat history
  // Returns a Stream for the current user's chat history. Resolves the
  // university id first and subscribes to the university-scoped path when
  // available, otherwise falls back to per-user chat_history.
  static Future<Stream<List<Map<String, String>>>> getChatHistoryStream() async {
    final uniId = await getUniversityId();
    if (uniId != null) {
      return _db
          .collection('universities')
          .doc(uniId)
          .collection('ai_planner')
          .doc(userId)
          .collection('chat_history')
          .orderBy('timestamp', descending: false)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => {
                    'role': doc['role'] as String,
                    'content': doc['content'] as String,
                  })
              .toList());
    }

    return _db
        .collection('users')
        .doc(userId)
        .collection('chat_history')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {
                  'role': doc['role'] as String,
                  'content': doc['content'] as String,
                })
            .toList());
  }

  // Fallback: get locally persisted chat history saved when Firestore writes failed.
  static Future<List<Map<String, String>>> getLocalChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uniId = await getUniversityId();
      final key = 'ai_chat_${uniId ?? userId}';
      final existing = prefs.getString(key);
      if (existing == null) return [];
      final raw = jsonDecode(existing) as List<dynamic>;
      return raw.map((e) => Map<String, String>.from(e)).toList();
    } catch (e) {
      debugPrint('Error reading local chat history: $e');
      return [];
    }
  }

  // Clear chat history both server-side (if available) and local fallback.
  static Future<void> clearChatHistory() async {
    try {
      final uniId = await getUniversityId();
      final uid = userId;
      if (uniId != null) {
        final coll = _db
            .collection('universities')
            .doc(uniId)
            .collection('ai_planner')
            .doc(uid)
            .collection('chat_history');
        final snap = await coll.get();
        final batch = _db.batch();
        for (var d in snap.docs) batch.delete(d.reference);
        await batch.commit();
      } else {
        final coll = _db.collection('users').doc(uid).collection('chat_history');
        final snap = await coll.get();
        final batch = _db.batch();
        for (var d in snap.docs) batch.delete(d.reference);
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Failed to clear chat history from Firestore: $e');
    }

    // Clear local SharedPreferences fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      final uniId = await getUniversityId();
      final key = 'ai_chat_${uniId ?? userId}';
      await prefs.remove(key);
    } catch (e) {
      debugPrint('Failed to clear local chat history: $e');
    }
  }

  // Save/Update user study data (prefer university-scoped `ai_planner` doc)
  static Future<void> updateStudyData(Map<String, dynamic> data) async {
    final uniId = await getUniversityId();
    if (uniId != null) {
      await _db
          .collection('universities')
          .doc(uniId)
          .collection('ai_planner')
          .doc(userId)
          .set(data, SetOptions(merge: true));
      return;
    }
    await _db.collection('users').doc(userId).set(data, SetOptions(merge: true));
  }

  // Get user study data stream (university-scoped when available)
  static Future<Stream<DocumentSnapshot>> getStudyDataStream() async {
    final uniId = await getUniversityId();
    if (uniId != null) {
      return _db
          .collection('universities')
          .doc(uniId)
          .collection('ai_planner')
          .doc(userId)
          .snapshots();
    }
    return _db.collection('users').doc(userId).snapshots();
  }

  // Save task under university-scoped ai_planner/tasks or per-user tasks
  static Future<void> saveTask(Map<String, dynamic> task) async {
    final uniId = await getUniversityId();
    if (uniId != null) {
        await _db
          .collection('universities')
          .doc(uniId)
          .collection('ai_planner')
          .doc(userId)
          .collection('tasks')
          .add({
        ...task,
        'duration_seconds': task['duration_seconds'] ?? task['duration'] ?? 1500,
        'created_at': FieldValue.serverTimestamp(),
      });
      return;
    }
    await _db.collection('users').doc(userId).collection('tasks').add({
      ...task,
      'duration_seconds': task['duration_seconds'] ?? task['duration'] ?? 1500,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  // Delete a task by id
  static Future<void> deleteTask(String taskId) async {
    final uniId = await getUniversityId();
    if (uniId != null) {
      await _db
          .collection('universities')
          .doc(uniId)
          .collection('ai_planner')
          .doc(userId)
          .collection('tasks')
          .doc(taskId)
          .delete();
      return;
    }
    await _db.collection('users').doc(userId).collection('tasks').doc(taskId).delete();
  }

  static Future<void> updateTaskDuration(String taskId, int seconds) async {
    final uniId = await getUniversityId();
    if (uniId != null) {
      await _db
          .collection('universities')
          .doc(uniId)
          .collection('ai_planner')
          .doc(userId)
          .collection('tasks')
          .doc(taskId)
          .update({'duration_seconds': seconds});
      return;
    }
    await _db.collection('users').doc(userId).collection('tasks').doc(taskId).update({'duration_seconds': seconds});
  }

  // Get tasks stream (university-scoped when available)
  static Future<Stream<List<Map<String, dynamic>>>> getTasksStream() async {
    final uniId = await getUniversityId();
    if (uniId != null) {
      return _db
          .collection('universities')
          .doc(uniId)
          .collection('ai_planner')
          .doc(userId)
          .collection('tasks')
          .orderBy('created_at', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => {
                    'id': doc.id,
                    ...doc.data(),
                  })
              .toList());
    }
    return _db
        .collection('users')
        .doc(userId)
        .collection('tasks')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {
                  'id': doc.id,
                  ...doc.data(),
                })
            .toList());
  }

  // Update task completion (university-scoped when available)
  static Future<void> updateTaskCompletion(String taskId, bool completed) async {
    final uniId = await getUniversityId();
    if (uniId != null) {
      await _db
          .collection('universities')
          .doc(uniId)
          .collection('ai_planner')
          .doc(userId)
          .collection('tasks')
          .doc(taskId)
          .update({'completed': completed});
      return;
    }
    await _db
        .collection('users')
        .doc(userId)
        .collection('tasks')
        .doc(taskId)
        .update({'completed': completed});
  }

  // Increment task duration (seconds) atomically
  static Future<void> incrementTaskDuration(String taskId, int seconds) async {
    final uniId = await getUniversityId();
    if (uniId != null) {
      await _db
          .collection('universities')
          .doc(uniId)
          .collection('ai_planner')
          .doc(userId)
          .collection('tasks')
          .doc(taskId)
          .update({'duration_seconds': FieldValue.increment(seconds)});
      return;
    }
    await _db
        .collection('users')
        .doc(userId)
        .collection('tasks')
        .doc(taskId)
        .update({'duration_seconds': FieldValue.increment(seconds)});
  }
}

// ============================================================================
// CHAT PROVIDER
// ============================================================================
class ChatProvider with ChangeNotifier {
  List<Map<String, String>> _messages = [
    {
      'role': 'assistant',
      'content': 'Hello! I\'m your AI study assistant. How can I help you plan your studies today?'
    }
  ];
  bool _isLoading = false;

  List<Map<String, String>> get messages => _messages;
  bool get isLoading => _isLoading;

  Future<void> clearHistory() async {
    // Clear server and local history, then reset in-memory messages
    try {
      await FirestoreService.clearChatHistory();
    } catch (e) {
      debugPrint('clearHistory: firestore clear failed: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final uniId = await FirestoreService.getUniversityId();
      final key = 'ai_chat_${uniId ?? FirestoreService.userId}';
      await prefs.remove(key);
    } catch (e) {
      debugPrint('clearHistory: prefs clear failed: $e');
    }

    _messages = [
      {
        'role': 'assistant',
        'content': 'Hello! I\'m your AI study assistant. How can I help you plan your studies today?'
      }
    ];
    notifyListeners();
  }

  ChatProvider() {
    _loadChatHistory();
  }

  Future<void> _loadChatHistory() async {
    try {
      final stream = await FirestoreService.getChatHistoryStream();
      stream.listen((history) {
        if (history.isEmpty) {
          _messages = [
            {
              'role': 'assistant',
              'content': 'Hello! I\'m your AI study assistant. How can I help you plan your studies today?'
            }
          ];
        } else {
          _messages = history;
        }
        notifyListeners();
      }, onError: (e) async {
        debugPrint('Firestore chat stream error: $e');
        final local = await FirestoreService.getLocalChatHistory();
        if (local.isEmpty) {
          _messages = [
            {
              'role': 'assistant',
              'content': 'Hello! I\'m your AI study assistant. How can I help you plan your studies today?'
            }
          ];
        } else {
          _messages = local;
        }
        notifyListeners();
      });
    } catch (e) {
      debugPrint('Error initializing chat history stream: $e');
      final local = await FirestoreService.getLocalChatHistory();
      if (local.isEmpty) {
        _messages = [
          {
            'role': 'assistant',
            'content': 'Hello! I\'m your AI study assistant. How can I help you plan your studies today?'
          }
        ];
      } else {
        _messages = local;
      }
      notifyListeners();
    }
  }

  Future<void> sendMessage(String message) async {
    final userMessage = {'role': 'user', 'content': message};
    _messages.add(userMessage);
    _isLoading = true;
    notifyListeners();

    try {
      // Attempt to save the user message but do not fail the whole flow on
      // Firestore errors — show a warning locally and continue.
      try {
        await FirestoreService.saveChatMessage(userMessage);
      } catch (e) {
        debugPrint('Warning: failed to save user message: $e');
      }

      final response = await GroqService.sendMessage(
        // Note: apiKey is omitted here to rely on the unified _resolveApiKey in GroqService
        userMessage: message,
        conversationHistory: _messages.sublist(0, _messages.length - 1),
      );

      String assistantContent = response.isNotEmpty ? response : '';
      // If API returned error-like text (e.g., 'Error: 400') or empty, try a local fallback
      if (assistantContent.isEmpty || assistantContent.startsWith('Error:')) {
        if (_looksLikeScheduleRequest(message)) {
          assistantContent = _generateLocalSchedule(message);
        } else {
          assistantContent = 'Sorry, I could not fetch an answer right now.';
        }
      }

      final assistantMessage = {'role': 'assistant', 'content': assistantContent};
      _messages.add(assistantMessage);

      try {
        await FirestoreService.saveChatMessage(assistantMessage);
      } catch (e) {
        debugPrint('Warning: failed to save assistant message: $e');
      }
    } catch (e) {
      _messages.add({
        'role': 'assistant',
        'content': 'Sorry, I encountered an error. Please try again.'
      });
      debugPrint('Chat sendMessage error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool _looksLikeScheduleRequest(String message) {
    final m = message.toLowerCase();
    // Accept common misspellings and short substrings so buttons like
    // "calculus shedule" still trigger the local schedule fallback.
    return m.contains('schedule') ||
        m.contains('sched') ||
        m.contains('shedule') ||
        m.contains('study plan') ||
        m.contains('timetable') ||
        m.contains('dsa') ||
        m.contains('data structures') ||
        m.contains('plan');
  }

  String _generateLocalSchedule(String message) {
    final m = message.toLowerCase();
    // If the user asked specifically for calculus/math, return a small
    // deterministic calculus schedule. Otherwise fall back to a DSA plan.
    if (m.contains('calculus') || m.contains('math') || m.contains('integration') || m.contains('derivative')) {
      return '''7-day Calculus study schedule (1.5 hours/day):

Day 1 — Limits & Continuity: read theory (30m), solve basic problems (30m), review (30m).
Day 2 — Derivatives: rules & applications (30m), practice problems (60m).
Day 3 — Advanced Derivatives: implicit, higher-order (30m), practice (60m).
Day 4 — Integrals: basic antiderivatives (30m), substitution practice (60m).
Day 5 — Techniques of Integration: parts, partial fractions (30m), practice (60m).
Day 6 — Applications: areas, volumes, rates (30m), mixed problems (60m).
Day 7 — Revision & Mock: mixed problem set (90m) + review (30m).

Tips: focus on problem types you struggle with, and time yourself on practice sets.''';
    }

    // Default fallback: DSA plan
    return '''7-day DSA study schedule (2 hours/day):

Day 1 — Arrays & Strings: concepts, practice easy problems (30m), one medium (60m), review (30m).
Day 2 — Linked Lists & Stacks: theory + easy problems (30m), medium (60m), review (30m).
Day 3 — Queues & Hashing: concepts + easy (30m), medium (60m), review (30m).
Day 4 — Trees (BST): traversal + easy (30m), medium (60m), review (30m).
Day 5 — Graphs basics: BFS/DFS + simple problems (30m), medium (60m), review (30m).
Day 6 — Dynamic Programming intro: patterns + easy (30m), medium (60m), review (30m).
Day 7 — Mock contest: 3 problems (90m) + analysis (30m).

Tips: practice with timed mocks, analyze wrong solutions, repeat weak topics next week.''';
  }
}

// ============================================================================
// STUDY DATA PROVIDER
// ============================================================================
class StudyResource {
  final String title;
  final String subtitle;
  final String url;
  final Color color;
  final IconData icon;

  StudyResource({required this.title, required this.subtitle, required this.url, required this.color, required this.icon});
}

class StudyDataProvider with ChangeNotifier {
  double _progress = 0.0;
  String _currentFocus = '';
  // Timer fields (seconds)
  static const int _defaultPomodoro = 25 * 60;
  static const int _breakDuration = 5 * 60;
  int _remainingSeconds = _defaultPomodoro;
  Timer? _timer;
  bool _isTimerRunning = false;
  bool _isBreakMode = false;
  bool get isBreakMode => _isBreakMode;
  bool _sessionFinished = false; // set when a focus session reaches 0 and awaits user confirmation
  bool get sessionFinished => _sessionFinished;
  List<Task> _tasks = [];
  // accumulate study seconds for today's updates
  int _accumulatedSecondsSincePersist = 0;
  int _taskSecondsSincePersist = 0;
  String? _selectedTaskId;
  String? get selectedTaskId => _selectedTaskId;
  // Performance spots for chart (FlSpot list) — keeps chart data easy to update
  List<FlSpot> _performanceSpots = List.generate(
      7, (i) => FlSpot(i.toDouble(), [2.0, 3.5, 2.5, 4.0, 3.0, 5.0, 4.5][i]));

  double get progress => _progress;
  String get currentFocus => _currentFocus;
  int get timerSeconds => _remainingSeconds;
  List<Task> get tasks => _tasks;
  List<FlSpot> get performanceSpots => _performanceSpots;
  bool get isTimerRunning => _isTimerRunning;

  // --- New: Graph data (7 days: Sun..Sat)
  List<double> studyHours = [2, 3.5, 4, 2, 5, 6, 4];
  List<double> focusTrends = [3, 4, 3, 5, 4, 7, 5];

  double get maxGraphValue {
    if (studyHours.isEmpty && focusTrends.isEmpty) return 6.0;
    double maxH = studyHours.isNotEmpty ? studyHours.reduce((a, b) => a > b ? a : b) : 0.0;
    double maxF = focusTrends.isNotEmpty ? focusTrends.reduce((a, b) => a > b ? a : b) : 0.0;
    final m = (maxH > maxF ? maxH : maxF) + 2.0;
    return m;
  }
  String? _lastTimerEvent; // 'success' or 'failed' or null
  String? get lastTimerEvent => _lastTimerEvent;

  StudyDataProvider() {
    _loadStudyData();
    _loadTasks();
    _initResources();
  }

  Future<void> _playNotification() async {
    // Try local asset first (uses the provided asset filename)
    try {
      final player = AudioPlayer();
      await player.play(AssetSource('sounds/700-hz-beeps-86815.mp3'));
      return;
    } catch (e) {
      debugPrint('Audio asset play failed (will fallback to system sound): $e');
    }

    // Fallback: play a system alert sound (may be a simple beep) and vibrate.
    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (e) {
      debugPrint('SystemSound failed: $e');
    }

    try {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 500);
      }
    } catch (e) {
      debugPrint('Vibration error: $e');
    }
  }

  // Predefined recommended resources
  final List<StudyResource> _resources = [];
  List<StudyResource> get resources => _resources;

  void _initResources() {
    _resources.clear();
    _resources.addAll([
      StudyResource(
        title: 'AI Study Roadmap',
        subtitle: 'Roadmap and learning paths',
        url: 'https://roadmap.sh/ai',
        color: kPrimaryColor,
        icon: Icons.auto_stories,
      ),
      StudyResource(
        title: 'LitCharts (Literature)',
        subtitle: 'Literature summaries & guides',
        url: 'https://www.litcharts.com',
        color: kSecondaryColor,
        icon: Icons.menu_book,
      ),
      StudyResource(
        title: 'Deep Research (Scholar)',
        subtitle: 'Academic search and papers',
        url: 'https://scholar.google.com',
        color: Colors.orange,
        icon: Icons.lightbulb,
      ),
    ]);
  }

  Future<void> launchLink(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      debugPrint('launchLink error: $e');
      rethrow;
    }
  }

  void _loadStudyData() {
    () async {
      try {
        final stream = await FirestoreService.getStudyDataStream();
        stream.listen((snapshot) {
          if (snapshot.exists) {
            final data = snapshot.data() as Map<String, dynamic>;
            _progress = (data['progress'] ?? 0.0).toDouble();
            _currentFocus = data['current_focus'] ?? '';
            _remainingSeconds = data['timer_seconds'] ?? _defaultPomodoro;
            if (data['performance_spots'] != null) {
              try {
                final raw = List<dynamic>.from(data['performance_spots']);
                _performanceSpots = raw
                    .map((e) => FlSpot((e['x'] as num).toDouble(), (e['y'] as num).toDouble()))
                    .toList();
              } catch (_) {}
            }
            // Load persisted study hours and focus trends if present
            if (data['study_hours'] != null) {
              try {
                final raw = List<dynamic>.from(data['study_hours']);
                final parsed = raw.map<double>((e) {
                  if (e is num) return e.toDouble();
                  return double.tryParse(e.toString()) ?? 0.0;
                }).toList();
                if (parsed.length >= 7) {
                  studyHours = parsed.sublist(0, 7);
                } else if (parsed.isNotEmpty) {
                  // pad to 7
                  studyHours = List<double>.from(parsed);
                  while (studyHours.length < 7) studyHours.add(0.0);
                }
              } catch (_) {}
            }
            if (data['focus_trends'] != null) {
              try {
                final raw = List<dynamic>.from(data['focus_trends']);
                final parsed = raw.map<double>((e) {
                  if (e is num) return e.toDouble();
                  return double.tryParse(e.toString()) ?? 0.0;
                }).toList();
                if (parsed.length >= 7) {
                  focusTrends = parsed.sublist(0, 7);
                } else if (parsed.isNotEmpty) {
                  focusTrends = List<double>.from(parsed);
                  while (focusTrends.length < 7) focusTrends.add(0.0);
                }
              } catch (_) {}
            }
            notifyListeners();
          }
        });
      } catch (e) {
        debugPrint('Error loading study data stream: $e');
      }
    }();
  }

  void _loadTasks() {
    () async {
      try {
        final stream = await FirestoreService.getTasksStream();
        stream.listen((taskList) {
          // incoming taskList is List<Map<String,dynamic>> from FirestoreService
          _tasks = taskList.map<Task>((m) {
            final dyn = m['duration_seconds'] ?? m['duration'] ?? 1500;
            int dur = 1500;
            try {
              if (dyn is num) dur = dyn.toInt();
              else if (dyn is String) dur = int.tryParse(dyn) ?? 1500;
            } catch (_) {
              dur = 1500;
            }
            return Task(
              id: m['id']?.toString(),
              title: (m['title'] ?? '').toString(),
              isCompleted: (m['completed'] ?? false) as bool,
              durationSeconds: dur,
            );
          }).toList();
          _recomputeProgress();
          notifyListeners();
        });
      } catch (e) {
        debugPrint('Error loading tasks stream: $e');
      }
    }();
  }

  void _recomputeProgress() {
    if (_tasks.isEmpty) {
      _progress = 0.0;
      return;
    }
    final done = _tasks.where((t) => t.isCompleted).length;
    _progress = done / _tasks.length;
  }

  // Toggle task checkbox by index and persist change if possible
  Future<void> toggleTask(int index) async {
    if (index < 0 || index >= _tasks.length) return;
    _tasks[index].isCompleted = !_tasks[index].isCompleted;
    _recomputeProgress();
    notifyListeners();
    final id = _tasks[index].id;
    if (id != null) {
      try {
        await FirestoreService.updateTaskCompletion(id, _tasks[index].isCompleted);
      } catch (e) {
        debugPrint('Failed to update task completion: $e');
      }
    }
  }

  Future<void> deleteTask(String id) async {
    _tasks.removeWhere((t) => t.id == id);
    _recomputeProgress();
    notifyListeners();
    try {
      await FirestoreService.deleteTask(id);
    } catch (e) {
      debugPrint('Failed to delete task: $e');
    }
  }

  void selectTask(String? id) {
    _selectedTaskId = id;
    if (id == null) return;
    final t = _tasks.firstWhere((e) => e.id == id, orElse: () => Task(title: '', durationSeconds: _defaultPomodoro));
    _remainingSeconds = t.durationSeconds;
    notifyListeners();
  }

  Future<void> setTaskDuration(String id, int seconds) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    _tasks[idx].durationSeconds = seconds;
    if (_selectedTaskId == id) {
      _remainingSeconds = seconds;
    }
    notifyListeners();
    try {
      await FirestoreService.updateTaskDuration(id, seconds);
    } catch (e) {
      debugPrint('Failed to persist task duration: $e');
    }
  }

  

  Future<void> addTask(String title) async {
    // optimistic add locally; Firestore stream will reconcile with server ids
    _tasks.insert(0, Task(title: title, isCompleted: false));
    _recomputeProgress();
    notifyListeners();
    try {
      await FirestoreService.saveTask({
        'title': title,
        'completed': false,
      });
    } catch (e) {
      debugPrint('Failed to persist new task: $e');
    }
  }

  Future<void> updateProgress(double newProgress) async {
    _progress = newProgress;
    await FirestoreService.updateStudyData({'progress': newProgress});
    notifyListeners();
  }

  Future<void> updateFocus(String newFocus) async {
    _currentFocus = newFocus;
    await FirestoreService.updateStudyData({'current_focus': newFocus});
    notifyListeners();
  }

  // ===== Timer controls =====
  void startTimer() {
    if (_isTimerRunning) return;
    _isTimerRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (_remainingSeconds > 0) {
        _remainingSeconds -= 1;
        // Track study time live: attribute seconds to today's entry and selected task
        try {
          if (!_isBreakMode) {
            // increment accumulators
            _accumulatedSecondsSincePersist += 1;
            // ensure studyHours has 7 entries
            if (studyHours.length < 7) studyHours = List<double>.filled(7, 0.0);
            final todayIndex = DateTime.now().weekday % 7; // Sun=0, Mon=1 ... Sat=6
            studyHours[todayIndex] = (studyHours[todayIndex]) + (1.0 / 3600.0);

            // if a task is selected, increment its tracked duration
            if (_selectedTaskId != null) {
              final ti = _tasks.indexWhere((t) => t.id == _selectedTaskId);
              if (ti != -1) {
                _tasks[ti].durationSeconds += 1;
                _taskSecondsSincePersist += 1;
              }
            }

            // Persist in batches every 15 seconds to avoid excessive writes
            if (_accumulatedSecondsSincePersist >= 15) {
              try {
                await FirestoreService.updateStudyData({'study_hours': studyHours});
              } catch (e) {
                debugPrint('Failed to persist study hours: $e');
              }
              _accumulatedSecondsSincePersist = 0;
            }

            if (_taskSecondsSincePersist >= 15 && _selectedTaskId != null) {
              try {
                await FirestoreService.updateTaskDuration(_selectedTaskId!, _taskSecondsSincePersist);
              } catch (e) {
                debugPrint('Failed to persist task duration increment: $e');
              }
              _taskSecondsSincePersist = 0;
            }
          }
        } catch (e) {
          debugPrint('Error tracking live study time: $e');
        }

        notifyListeners();
      } else {
        // stop at zero and trigger session behavior
        pauseTimer();
        // Play notification and set sessionFinished to allow the UI to ask the user.
        try {
          await _playNotification();
        } catch (_) {}
        if (!_isBreakMode) {
          // Focus session ended — wait for user confirmation to mark task done
          _sessionFinished = true;
          _lastTimerEvent = 'session_complete';
          notifyListeners();
        } else {
          // Break ended — notify and return to focus mode (reset to default)
          _lastTimerEvent = 'break_complete';
          _sessionFinished = false;
          _isBreakMode = false;
          _remainingSeconds = _defaultPomodoro;
          // alert user (again)
          try {
            await _playNotification();
          } catch (_) {}
          notifyListeners();
        }
      }
    });
    notifyListeners();
  }

  void pauseTimer() {
    _timer?.cancel();
    _timer = null;
    _isTimerRunning = false;
    // Persist any accumulated study seconds and task seconds
    try {
      if (_accumulatedSecondsSincePersist > 0) {
        FirestoreService.updateStudyData({'study_hours': studyHours});
        _accumulatedSecondsSincePersist = 0;
      }
    } catch (e) {
      debugPrint('Failed to persist study hours on pause: $e');
    }
    try {
      if (_taskSecondsSincePersist > 0 && _selectedTaskId != null) {
        FirestoreService.updateTaskDuration(_selectedTaskId!, _taskSecondsSincePersist);
        _taskSecondsSincePersist = 0;
      }
    } catch (e) {
      debugPrint('Failed to persist task duration on pause: $e');
    }
    notifyListeners();
  }

  void resetTimer([int? seconds]) {
    pauseTimer();
    _remainingSeconds = seconds ?? _defaultPomodoro;
    notifyListeners();
  }

  /// Call this to handle the user's choice after a focus session finishes.
  /// If [markDone] is true, the selected task will be marked completed.
  Future<void> handleSessionDialogResult(bool markDone) async {
    _sessionFinished = false;
    if (markDone && _selectedTaskId != null) {
      try {
        await completeSelectedTask();
      } catch (e) {
        debugPrint('Error marking task complete after session: $e');
      }
    }
    // Persist any remaining accumulated seconds
    try {
      if (_accumulatedSecondsSincePersist > 0) {
        await FirestoreService.updateStudyData({'study_hours': studyHours});
        _accumulatedSecondsSincePersist = 0;
      }
    } catch (e) {
      debugPrint('Failed to persist study hours on session end: $e');
    }
    try {
      if (_taskSecondsSincePersist > 0 && _selectedTaskId != null) {
        await FirestoreService.updateTaskDuration(_selectedTaskId!, _taskSecondsSincePersist);
        _taskSecondsSincePersist = 0;
      }
    } catch (e) {
      debugPrint('Failed to persist task duration on session end: $e');
    }

    // Enter break mode
    _isBreakMode = true;
    _remainingSeconds = _breakDuration;
    notifyListeners();
    // start break timer automatically
    startTimer();
  }

  Future<void> completeSelectedTask() async {
    if (_selectedTaskId == null) return;
    final idx = _tasks.indexWhere((t) => t.id == _selectedTaskId);
    if (idx == -1) return;
    _tasks[idx].isCompleted = true;
    _recomputeProgress();
    notifyListeners();
    try {
      final id = _tasks[idx].id;
      if (id != null) await FirestoreService.updateTaskCompletion(id, true);
    } catch (e) {
      debugPrint('Failed to persist task completion: $e');
    }
  }

  // Called when user marks a failure; stops timer and exposes event for UI.
  void failTimer() {
    pauseTimer();
    _lastTimerEvent = 'failed';
    notifyListeners();
  }

  // extend by extra seconds and resume
  void extendTimer(int extraSeconds) {
    _remainingSeconds += extraSeconds;
    _lastTimerEvent = null;
    startTimer();
    notifyListeners();
  }

  void clearLastTimerEvent() {
    _lastTimerEvent = null;
    notifyListeners();
  }

  // ===== Create New Plan via AI =====
  bool _isLoadingPlan = false;
  bool get isLoadingPlan => _isLoadingPlan;

  Future<void> createNewPlan({String subject = 'Physics', int days = 7, int minutesPerSession = 60}) async {
    _isLoadingPlan = true;
    notifyListeners();
    try {
      final prompt = 'Generate a ${days}-day study schedule for $subject. Each day should have concise tasks and recommended session lengths in minutes. Aim for sessions around ${minutesPerSession} minutes but vary between 20-90 minutes based on topic difficulty. Return as numbered lines (one task per line).';
      final res = await GroqService.sendMessage(apiKey: groqApiKey, userMessage: prompt);
      String content = res;
      if (content.startsWith('Error:') || content.isEmpty) {
        // fallback simple plan
        content = '1. Read chapter on kinematics\n2. Solve 5 example problems\n3. Revise with flashcards';
      }

      // Parse lines into tasks
      final lines = content.split(RegExp(r'\r?\n'));
      final parsed = <Task>[];
      for (var line in lines) {
        var t = line.trim();
        if (t.isEmpty) continue;
        // strip leading numbering or bullets
        t = t.replaceFirst(RegExp(r'^[\d\)\.\-\s]+'), '');
        if (t.isEmpty) continue;
        parsed.add(Task(title: t));
      }

      if (parsed.isNotEmpty) {
        // Replace local tasks and try to persist
        _tasks = parsed;
        _recomputeProgress();
        notifyListeners();
        for (var t in parsed) {
          try {
            await FirestoreService.saveTask({'title': t.title, 'completed': false});
          } catch (e) {
            debugPrint('Failed to save generated plan task: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('createNewPlan error: $e');
    } finally {
      _isLoadingPlan = false;
      notifyListeners();
    }
  }

  Future<String> suggestTask({String contextHint = 'a short study task'}) async {
    try {
      final prompt = 'Provide one concise study task: $contextHint. Return as one short sentence.';
      final res = await GroqService.sendMessage(apiKey: groqApiKey, userMessage: prompt);
      if (res.startsWith('Error:') || res.trim().isEmpty) return '';
      // take first non-empty line
      final lines = res.split(RegExp(r'\r?\n'));
      for (var l in lines) {
        final t = l.trim();
        if (t.isEmpty) continue;
        return t.replaceFirst(RegExp(r'^[\d\)\.\-\s]+'), '');
      }
      return res.trim();
    } catch (e) {
      debugPrint('suggestTask error: $e');
      return '';
    }
  }
}

// ============================================================================
// MAIN STUDY PLANNER PAGE
// ============================================================================
class StudyPlannerPage extends StatelessWidget {
  const StudyPlannerPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: getAppBackgroundColor(context),
      appBar: AppBar(
        backgroundColor: getAppBackgroundColor(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: getAppTextColor(context)),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'AI Study Planner',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: getAppTextColor(context),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, color: getAppTextColor(context)),
              onPressed: () async {
                await showDialog<void>(
                  context: context,
                  builder: (c) => const _ApiKeySettingsDialog(),
                );
              },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Row: Progress/Create Plan (Left) + Focus Timer (Right)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        ProgressCard(),
                        const SizedBox(height: 12),
                        CreatePlanCard(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: FocusCard()),
                ],
              ),
              const SizedBox(height: 12),
              
              // Tasks - Full Width
              TasksCard(),
              const SizedBox(height: 12),
              
              // Chat Interface
              ChatInterface(),
              const SizedBox(height: 12),
              
              // Analytics
              AnalyticsPanel(),
              const SizedBox(height: 12),
              
              // Resources
              ResourcesCard(),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PROGRESS CARD
// ============================================================================
class ProgressCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<StudyDataProvider>(
      builder: (context, provider, _) {
        final container = Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimaryColor.withOpacity(0.8), kSecondaryColor.withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: kPrimaryColor.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Study Plan',
                style: GoogleFonts.poppins(
                  color: kWhiteColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: provider.progress,
                backgroundColor: kWhiteColor.withOpacity(0.3),
                valueColor: AlwaysStoppedAnimation<Color>(kWhiteColor),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 12),
              Text(
                '${(provider.progress * 100).toInt()}% Completed',
                style: GoogleFonts.poppins(
                  color: kWhiteColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );

        // Show mission dialogs when provider reports timer events
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (provider.lastTimerEvent == 'success') {
            provider.clearLastTimerEvent();
            await showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Mission Success!'),
                content: const Text('Well done — you completed the task in time.'),
                actions: [ElevatedButton(onPressed: () => Navigator.of(c).pop(), child: const Text('OK'))],
              ),
            );
          } else if (provider.lastTimerEvent == 'failed') {
            // Clear the provider flag so UI doesn't repeatedly show the prompt
            provider.clearLastTimerEvent();

            // Show a lightweight SnackBar (toast-like) with quick action
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text("Time's up — you can extend your time."),
                action: SnackBarAction(
                  label: 'Extend 5m',
                  onPressed: () => provider.extendTimer(5 * 60),
                ),
                duration: const Duration(seconds: 4),
              ),
            );

            // Then show a beautiful bottom sheet with extend options
            await showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (c) => DraggableScrollableSheet(
                initialChildSize: 0.28,
                minChildSize: 0.18,
                maxChildSize: 0.6,
                expand: false,
                builder: (_, controller) => Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [kPrimaryColor.withOpacity(0.95), kSecondaryColor.withOpacity(0.95)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(height: 4, width: 56, decoration: BoxDecoration(color: kWhiteColor.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
                      const SizedBox(height: 12),
                      Text("Time's Up!", style: GoogleFonts.poppins(color: kWhiteColor, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text("Looks like your session ended. Would you like to add more time?",
                          textAlign: TextAlign.center, style: GoogleFonts.poppins(color: kWhiteColor.withOpacity(0.95), fontSize: 13)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: kWhiteColor.withOpacity(0.12)),
                            onPressed: () {
                              provider.extendTimer(5 * 60);
                              Navigator.of(c).pop();
                            },
                            child: Text('Extend 5 min', style: GoogleFonts.poppins(color: kWhiteColor)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: kWhiteColor.withOpacity(0.12)),
                            onPressed: () {
                              provider.extendTimer(10 * 60);
                              Navigator.of(c).pop();
                            },
                            child: Text('Extend 10 min', style: GoogleFonts.poppins(color: kWhiteColor)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.of(c).pop(),
                        child: Text('Dismiss', style: GoogleFonts.poppins(color: kWhiteColor.withOpacity(0.9))),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
        });

        return container;
      },
    );
  }
}

// Simple dialog to let an APK user enter/store the GROQ API key at runtime.
class _ApiKeySettingsDialog extends StatefulWidget {
  const _ApiKeySettingsDialog({Key? key}) : super(key: key);

  @override
  State<_ApiKeySettingsDialog> createState() => _ApiKeySettingsDialogState();
}

class _ApiKeySettingsDialogState extends State<_ApiKeySettingsDialog> {
  final _controller = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _controller.text = prefs.getString('GROQ_API_KEY') ?? '';
    } catch (e) {
      debugPrint('Failed to load GROQ_API_KEY: $e');
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('GROQ_API_KEY', _controller.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GROQ API key saved')));
      }
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Failed to save GROQ_API_KEY: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save API key')));
      }
    }
  }

  Future<void> _clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('GROQ_API_KEY');
      _controller.text = '';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GROQ API key cleared')));
      }
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Failed to clear GROQ_API_KEY: $e');
    }
  }

  Future<void> _testKey() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter an API key to test')));
      return;
    }
    setState(() => _loading = true);
    try {
      final models = await GroqService.listModels(apiKey: key);
      if (models.isNotEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Key valid — ${models.length} models available')));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Key appears invalid or returned no models')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error testing key: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI Configuration'),
      content: _loading
          ? const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enter your GROQ API key to enable AI features.'),
                const SizedBox(height: 12),
                TextField(
                  controller: _controller,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'GROQ API Key',
                    hintText: 'sk-...',
                  ),
                ),
              ],
            ),
      actions: [
        TextButton(onPressed: _clear, child: const Text('Clear')),
        TextButton(
          onPressed: _loading ? null : _testKey,
          child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Test'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

// ============================================================================
// FOCUS CARD
// ============================================================================
class FocusCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<StudyDataProvider>(
      builder: (context, provider, _) {
        // If a focus session just finished, prompt the user once.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (provider.sessionFinished) {
            showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) {
                return AlertDialog(
                  title: const Text('Session Complete!'),
                  content: const Text('Great job! Did you finish your current task?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('No, Keep Pending'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Yes, Mark Done'),
                    ),
                  ],
                );
              },
            ).then((value) {
              // treat null as false
              provider.handleSessionDialogResult(value == true);
            });
          }
        });

        Task? selected;
        if (provider.selectedTaskId == null) {
          selected = null;
        } else {
          final idx = provider.tasks.indexWhere((t) => t.id == provider.selectedTaskId);
          selected = idx == -1 ? null : provider.tasks[idx];
        }

        final isMobile = MediaQuery.of(context).size.width < 800;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: provider.isBreakMode
                  ? [Colors.green.withOpacity(0.9), Colors.lightGreen.withOpacity(0.8)]
                  : [kSecondaryColor.withOpacity(0.8), kPrimaryColor.withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: kSecondaryColor.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider.isBreakMode ? 'Break Time ☕' : 'Current Focus',
                style: GoogleFonts.poppins(
                  color: kWhiteColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                provider.currentFocus,
                style: GoogleFonts.poppins(
                  color: kWhiteColor,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    Text(
                      selected != null ? selected.title : 'No task selected',
                      style: GoogleFonts.poppins(color: kWhiteColor, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () {
                        if (provider.timerSeconds > 0) {
                          if (provider.isTimerRunning) {
                            provider.pauseTimer();
                          } else {
                            provider.startTimer();
                          }
                        }
                      },
                      child: Container(
                        width: isMobile ? 84 : 100,
                        height: isMobile ? 84 : 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                            border: Border.all(color: kWhiteColor, width: 4),
                            color: provider.isBreakMode ? Colors.greenAccent.withOpacity(0.1) : Colors.transparent,
                        ),
                        child: Center(
                          child: Text(
                            '${provider.timerSeconds ~/ 60}:${(provider.timerSeconds % 60).toString().padLeft(2, '0')}',
                            style: GoogleFonts.poppins(
                              color: kWhiteColor,
                              fontSize: isMobile ? 16 : 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor),
                          onPressed: () async {
                            // Set time for selected task
                            if (provider.selectedTaskId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a task first')));
                              return;
                            }
                            final minutesController = TextEditingController(text: (provider.timerSeconds ~/ 60).toString());
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Set Timer (minutes)'),
                                content: TextField(controller: minutesController, keyboardType: TextInputType.number),
                                actions: [TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Set'))],
                              ),
                            );
                            if (ok == true) {
                              final mins = int.tryParse(minutesController.text) ?? 25;
                              provider.setTaskDuration(provider.selectedTaskId!, mins * 60);
                            }
                          },
                          child: const Text('Set Time',style: TextStyle(color: Colors.white),),
                        ),
                        const SizedBox(width: 8),
                        // Removed 'Fail' button — failures now prompt a styled extend sheet automatically.
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// TASKS CARD
// ============================================================================
class TasksCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<StudyDataProvider>(
      builder: (context, provider, _) {
        final isMobile = MediaQuery.of(context).size.width < 800;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: getAppCardColor(context),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Upcoming Tasks',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: getAppTextColor(context),
                ),
              ),
              const SizedBox(height: 16),
              if (provider.tasks.isEmpty)
                Text(
                  'No tasks yet. Add your first task!',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                )
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: SingleChildScrollView(
                    child: Column(
                      children: provider.tasks.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final task = entry.value;
                        final selected = provider.selectedTaskId == task.id;
                        return ListTile(
                          contentPadding: EdgeInsets.symmetric(vertical: isMobile ? 10 : 6, horizontal: 8),
                          leading: Transform.scale(
                            scale: isMobile ? 1.2 : 1.0,
                            child: Checkbox(
                              value: task.isCompleted,
                              activeColor: kPrimaryColor,
                              onChanged: (v) => provider.toggleTask(idx),
                            ),
                          ),
                          title: Text(
                            task.title, 
                            style: GoogleFonts.poppins(
                              fontSize: isMobile ? 16 : 14,
                              color: getAppTextColor(context),
                            ),
                          ),
                          subtitle: Text(
                            '${(task.durationSeconds ~/ 60)} min', 
                            style: GoogleFonts.poppins(
                              fontSize: isMobile ? 13 : 12,
                              color: getAppTextColor(context).withOpacity(0.7),
                            ),
                          ),
                          tileColor: selected ? kPrimaryColor.withOpacity(0.08) : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Show playing/paused state only for the selected task
                              Builder(builder: (_) {
                                final isSelected = provider.selectedTaskId == task.id;
                                final isRunningForThis = isSelected && provider.isTimerRunning;
                                return IconButton(
                                  icon: Icon(
                                    isRunningForThis ? Icons.pause : Icons.play_arrow,
                                    color: isRunningForThis ? Colors.orange : Colors.green,
                                  ),
                                  onPressed: () {
                                    if (isRunningForThis) {
                                      provider.pauseTimer();
                                    } else {
                                      provider.selectTask(task.id);
                                      provider.startTimer();
                                    }
                                  },
                                  tooltip: isRunningForThis ? 'Pause timer' : 'Start timer for this task',
                                );
                              }),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text('Delete Task'),
                                      content: const Text('Delete this task permanently?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
                                        ElevatedButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Delete')),
                                      ],
                                    ),
                                  );
                                  if (confirm == true && task.id != null) {
                                    await provider.deleteTask(task.id!);
                                  }
                                },
                              ),
                            ],
                          ),
                          onTap: () => provider.selectTask(task.id),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              const SizedBox(height: 8),

            ],
          ),
        );
      },
    );
  }

  void _showAddTaskDialog(BuildContext context) {
    final controller = TextEditingController();
    // Capture provider once to avoid ancestor lookups after async awaits
    final StudyDataProvider _studyProvider = Provider.of<StudyDataProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Add New Task', style: GoogleFonts.poppins()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'Task title'),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            // AI suggestion removed — manual entry only
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                // use captured provider instance to avoid ancestor lookup after async
                _studyProvider.addTask(controller.text);
                Navigator.pop(dialogContext);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CREATE PLAN CARD
// ============================================================================
class CreatePlanCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    return InkWell(
      onTap: () async {
        // AI option removed — open manual plan dialog directly
        final controller = TextEditingController();
        final saved = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Create Plan Manually', style: GoogleFonts.poppins()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Enter tasks, one per line:', style: GoogleFonts.poppins(fontSize: 13)),
                const SizedBox(height: 8),
                TextField(controller: controller, maxLines: 6, decoration: const InputDecoration(hintText: 'e.g. Read chapter on kinematics\nSolve 5 example problems\nRevise with flashcards', border: OutlineInputBorder())),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
              ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor), onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Save', style: TextStyle(color: Colors.white))),
            ],
          ),
        );

        if (saved == true) {
          final text = controller.text.trim();
          if (text.isNotEmpty) {
            final lines = text.split(RegExp(r'\r?\n'));
            final provider = Provider.of<StudyDataProvider>(context, listen: false);
            for (var line in lines) {
              final t = line.trim();
              if (t.isEmpty) continue;
              await provider.addTask(t);
            }
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan saved to Upcoming Tasks')));
          }
        }
      },
      child: Container(
        width: 200,
        height: isMobile ? 130 : 200,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [kPrimaryColor, kSecondaryColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: kPrimaryColor.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.psychology, size: 60, color: kWhiteColor),
            const SizedBox(height: 16),
            Text(
              'Create New Plan',
              style: GoogleFonts.poppins(
                color: kWhiteColor,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// CHAT INTERFACE
// ============================================================================
class ChatInterface extends StatefulWidget {
  @override
  State<ChatInterface> createState() => _ChatInterfaceState();
}

class _ChatInterfaceState extends State<ChatInterface> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isMaximized = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Guard: if ChatProvider is not available in this context, show a
    // non-crashing placeholder that lets the user open the full chat page.
    ChatProvider? _maybeProvider;
    try {
      _maybeProvider = Provider.of<ChatProvider>(context);
    } catch (_) {
      _maybeProvider = null;
    }

    if (_maybeProvider == null) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 180,
        decoration: BoxDecoration(
          color: getAppCardColor(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5)),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('AI Assistant is initializing...', style: GoogleFonts.poppins(color: getAppTextColor(context))),
              const SizedBox(height: 8),
                  ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor),
                onPressed: () {
                  // Navigate to the standalone AI Study Planner module which
                  // ensures providers are created at the module level.
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StudyPlannerModule()));
                },
                child: Text('Open Chat', style: GoogleFonts.poppins()),
              ),
            ],
          ),
        ),
      );
    }

    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        _scrollToBottom();
        
        final screenH = MediaQuery.of(context).size.height;
        final screenW = MediaQuery.of(context).size.width;
        final bool isNarrow = screenW < 800;
        final double adaptiveHeight = isNarrow ? min(360.0, screenH * 0.38) : min(420.0, screenH * 0.45);
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: _isMaximized ? screenH - 80 : adaptiveHeight,
          decoration: BoxDecoration(
            color: getAppCardColor(context),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              // Chat header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kPrimaryColor.withOpacity(0.1), kSecondaryColor.withOpacity(0.1)],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.smart_toy, color: kPrimaryColor),
                    const SizedBox(width: 8),
                    Text(
                      'AI Assistant',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: getAppTextColor(context),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Maximize chat',
                      icon: Icon(_isMaximized ? Icons.fullscreen_exit : Icons.fullscreen, color: kPrimaryColor),
                      onPressed: () async {
                        if (!_isMaximized) {
                          setState(() {
                            _isMaximized = true;
                          });
                          // Try to reuse existing ChatProvider; if unavailable,
                          // create a new provider so the full-screen page still works.
                          try {
                            final existing = context.read<ChatProvider>();
                            await Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (c) => ChangeNotifierProvider.value(
                                value: existing,
                                child: ChatFullScreenPage(),
                              ),
                              fullscreenDialog: true,
                            ));
                          } catch (_) {
                            await Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (c) => ChangeNotifierProvider(create: (_) => ChatProvider(), child: ChatFullScreenPage()),
                              fullscreenDialog: true,
                            ));
                          }
                          // When the full-screen page is popped, restore local state.
                          if (mounted) {
                            setState(() {
                              _isMaximized = false;
                            });
                          }
                        } else {
                          Navigator.of(context).maybePop();
                        }
                      },
                    ),
                    IconButton(
                      tooltip: 'Clear chat history',
                      icon: Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Clear Chat History'),
                            content: const Text('Are you sure you want to permanently delete your chat history? This cannot be undone.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
                              ElevatedButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Delete')),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          try {
                            await provider.clearHistory();
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat history cleared')));
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to clear chat history')));
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              
              // Chat messages
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: provider.messages.length,
                  itemBuilder: (context, index) {
                    final message = provider.messages[index];
                    final isUser = message['role'] == 'user';
                    
                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.35,
                        ),
                        decoration: BoxDecoration(
                          color: isUser 
                            ? kPrimaryColor 
                            : (isDark ? Colors.grey[800] : Colors.grey[100]),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          message['content']!,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: isUser ? kWhiteColor : getAppTextColor(context),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              
              if (provider.isLoading)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'AI is thinking...',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              
              // Input area
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[200]!)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: TextStyle(color: getAppTextColor(context)),
                        decoration: InputDecoration(
                          hintText: 'Type your message...',
                          hintStyle: GoogleFonts.poppins(fontSize: 14, color: Colors.grey),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide(color: kPrimaryColor),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (value) => _sendMessage(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: kPrimaryColor,
                      child: IconButton(
                        icon: const Icon(Icons.send, color: kWhiteColor, size: 20),
                        onPressed: () => _sendMessage(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _sendMessage(BuildContext context) {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      context.read<ChatProvider>().sendMessage(text);
      _controller.clear();
    }
  }
}

// ============================================================================
// ANALYTICS PANEL
// ============================================================================
// Full-screen chat page shown when user maximizes the chat.
class ChatFullScreenPage extends StatefulWidget {
  @override
  State<ChatFullScreenPage> createState() => _ChatFullScreenPageState();
}

class _ChatFullScreenPageState extends State<ChatFullScreenPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage(BuildContext context) {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      context.read<ChatProvider>().sendMessage(text);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: getAppBackgroundColor(context),
      appBar: AppBar(
        title: Text('AI Assistant', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: getAppTextColor(context))),
        backgroundColor: getAppBackgroundColor(context),
        actions: [
          IconButton(
            icon: Icon(Icons.fullscreen_exit, color: getAppTextColor(context)),
            onPressed: () => Navigator.of(context).pop(),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Clear Chat History'),
                  content: const Text('Are you sure you want to permanently delete your chat history? This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
                    ElevatedButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Delete')),
                  ],
                ),
              );
              if (confirm == true) {
                try {
                  await context.read<ChatProvider>().clearHistory();
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat history cleared')));
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to clear chat history')));
                }
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Consumer<ChatProvider>(
          builder: (context, provider, _) {
            _scrollToBottom();
            return Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: provider.messages.length,
                    itemBuilder: (context, index) {
                      final message = provider.messages[index];
                      final isUser = message['role'] == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                          decoration: BoxDecoration(
                            color: isUser 
                                ? kPrimaryColor 
                                : (isDark ? Colors.grey[800] : Colors.grey[100]),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            message['content']!,
                            style: GoogleFonts.poppins(
                                fontSize: 14, 
                                color: isUser ? kWhiteColor : getAppTextColor(context)
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (provider.isLoading)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('AI is thinking...', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[200]!))),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          style: TextStyle(color: getAppTextColor(context)),
                          decoration: InputDecoration(
                            hintText: 'Type your message...',
                            hintStyle: GoogleFonts.poppins(fontSize: 14, color: Colors.grey),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: kPrimaryColor)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          onSubmitted: (_) => _sendMessage(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: kPrimaryColor,
                        child: IconButton(
                          icon: const Icon(Icons.send, color: kWhiteColor, size: 20),
                          onPressed: () => _sendMessage(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
class AnalyticsPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Performance Chart
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: getAppCardColor(context),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Analyze Performance',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: getAppTextColor(context),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 200,
                child: Consumer<StudyDataProvider>(
                  builder: (context, provider, _) {
                    // Build dynamic spots from provider data
                    final studySpots = List<FlSpot>.generate(
                      provider.studyHours.length,
                      (i) => FlSpot(i.toDouble(), provider.studyHours[i]),
                    );
                    final focusSpots = List<FlSpot>.generate(
                      provider.focusTrends.length,
                      (i) => FlSpot(i.toDouble(), provider.focusTrends[i]),
                    );

                    return LineChart(
                      LineChartData(
                        gridData: FlGridData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              interval: 1,
                              getTitlesWidget: (value, meta) {
                                // show only integer y labels to avoid clutter
                                if ((value - value.toInt()).abs() > 0.001) return const SizedBox();
                                return Text(
                                  value.toInt().toString(),
                                  style: GoogleFonts.poppins(fontSize: 10, color: getAppTextColor(context)),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: 1,
                              getTitlesWidget: (value, meta) {
                                // only show labels for whole-number x positions
                                final intIndex = value.toInt();
                                const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
                                if ((value - intIndex).abs() > 0.001) return const SizedBox();
                                if (intIndex >= 0 && intIndex < days.length) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      days[intIndex],
                                      style: GoogleFonts.poppins(fontSize: 10, color: getAppTextColor(context)),
                                    ),
                                  );
                                }
                                return const SizedBox();
                              },
                            ),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: studySpots,
                            isCurved: true,
                            color: kPrimaryColor,
                            barWidth: 3,
                            dotData: FlDotData(show: true),
                            belowBarData: BarAreaData(
                              show: true,
                              color: kPrimaryColor.withOpacity(0.2),
                            ),
                          ),
                          LineChartBarData(
                            spots: focusSpots,
                            isCurved: true,
                            color: kSecondaryColor,
                            barWidth: 2,
                            dotData: FlDotData(show: true),
                            belowBarData: BarAreaData(show: false),
                          ),
                        ],
                        minX: 0,
                        maxX: (provider.studyHours.length - 1).toDouble(),
                        minY: 0,
                        maxY: provider.maxGraphValue,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        // Recommended Resources moved to bottom as ResourcesCard for mobile
      ],
    );
  }

  Widget _buildResourceItem({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: kWhiteColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: kDarkTextColor,
              ),
            ),
          ),
          Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
        ],
      ),
    );
  }

  Widget _buildResourceItemFromResource(BuildContext context, StudyResource r) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: r.color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: r.color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(r.icon, color: kWhiteColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () async {
                try {
                  await Provider.of<StudyDataProvider>(context, listen: false).launchLink(r.url);
                } catch (_) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open ${r.title}')));
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: kDarkTextColor)),
                  const SizedBox(height: 4),
                  Text(r.subtitle, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () async {
              try {
                await Provider.of<StudyDataProvider>(context, listen: false).launchLink(r.url);
              } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open ${r.title}')));
              }
            },
            child: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// RESOURCES CARD (mobile full-width)
// ============================================================================
class ResourcesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<StudyDataProvider>(builder: (context, provider, _) {
      final resources = provider.resources;
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: getAppCardColor(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recommended Resources', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: getAppTextColor(context))),
            const SizedBox(height: 16),
            if (resources.isEmpty)
              Text('No recommended resources available.', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]))
            else
              Column(
                children: resources.map((r) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: InkWell(
                      onTap: () async {
                        try {
                          await provider.launchLink(r.url);
                        } catch (_) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open ${r.title}')));
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: r.color.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: r.color, borderRadius: BorderRadius.circular(8)),
                              child: Icon(r.icon, color: kWhiteColor, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(
                                  r.title, 
                                  style: GoogleFonts.poppins(
                                    fontSize: 13, 
                                    fontWeight: FontWeight.w600, 
                                    color: getAppTextColor(context)
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(r.subtitle, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
                              ]),
                            ),
                            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      );
    });
  }
}