// PART 1: ADMIN INVITE GENERATION SCREEN
// admin_faculty_invite_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AdminFacultyInviteScreen extends StatefulWidget {
  const AdminFacultyInviteScreen({super.key});

  @override
  State<AdminFacultyInviteScreen> createState() => _AdminFacultyInviteScreenState();
}

class _AdminFacultyInviteScreenState extends State<AdminFacultyInviteScreen> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _departmentController = TextEditingController();
  
  bool _isGenerating = false;
  String? _generatedCode;
  String? _adminUniId;

  @override
  void initState() {
    super.initState();
    _loadAdminUniId();
  }

  // Get admin's university ID
  Future<void> _loadAdminUniId() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (doc.exists) {
        setState(() {
          _adminUniId = doc.data()?['uniId'] as String?;
        });
      }
    } catch (e) {
      debugPrint('Error loading admin uni ID: $e');
    }
  }

  // Generate invite code WITHOUT sending email
  Future<void> _generateInviteCode() async {
    final email = _emailController.text.trim();
    final name = _nameController.text.trim();
    final dept = _departmentController.text.trim();

    if (email.isEmpty) {
      Get.snackbar('Error', 'Please enter professor email',
          backgroundColor: Colors.red.shade100);
      return;
    }

    // Basic email validation
    final emailRegex = RegExp(r"^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}");
    if (!emailRegex.hasMatch(email)) {
      Get.snackbar('Error', 'Please enter a valid email address',
          backgroundColor: Colors.orange.shade100);
      return;
    }

    if (_adminUniId == null) {
      Get.snackbar('Error', 'Could not determine your university',
          backgroundColor: Colors.red.shade100);
      return;
    }

    setState(() => _isGenerating = true);

    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    // Early check: ensure user is authenticated
    if (currentUid == null) {
      String projId = 'unknown';
      try {
        projId = Firebase.app().options.projectId;
      } catch (_) {}
      final msg = 'Not signed in (currentUid is null). Firebase project: $projId';
      debugPrint(msg);
      _showFailureDialog('Not Authenticated', msg, currentUid, _adminUniId);
      return;
    }

    debugPrint('Attempting to generate invite - currentUid: $currentUid, adminUniId: $_adminUniId');

    // Quick debug write to detect permission/internal errors before creating the real invite
    final debugDocRef = FirebaseFirestore.instance.collection('debug_invites').doc();
    try {
      await debugDocRef.set({
        'debug': true,
        'ts': FieldValue.serverTimestamp(),
        'createdBy': currentUid,
      });
      // remove debug doc immediately
      await debugDocRef.delete();
      debugPrint('Debug write succeeded');
    } on FirebaseException catch (fe) {
      debugPrint('Debug write FirestoreException: ${fe.code} ${fe.message}');
      final errMsg = 'Debug write failed: ${fe.code}: ${fe.message ?? 'internal'}';
      _showFailureDialog('Firestore Debug Write Failed', errMsg, currentUid, _adminUniId);
      setState(() => _isGenerating = false);
      return;
    } catch (e) {
      debugPrint('Debug write unknown error: $e');
      _showFailureDialog('Debug Write Error', e.toString(), currentUid, _adminUniId);
      setState(() => _isGenerating = false);
      return;
    }

    try {
      // Generate unique code
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final code = 'FAC-${timestamp.toString().substring(8)}';

      // Prepare invite payload
      final inviteData = {
        'code': code,
        'email': email.toLowerCase(),
        'facultyName': name.isEmpty ? 'Professor' : name,
        'department': dept.isEmpty ? 'Not specified' : dept,
        'uniId': _adminUniId,
        'isUsed': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': currentUid,
      };

      try {
        await FirebaseFirestore.instance.collection('invites').add(inviteData);
      } on FirebaseException catch (fe) {
        debugPrint('FirestoreException while creating invite: ${fe.code} ${fe.message}');
        final errMsg = '${fe.code}: ${fe.message ?? 'internal'}';
        Get.snackbar('Error', 'Failed to generate code (${fe.code}): ${fe.message ?? 'internal'}',
            backgroundColor: Colors.red.shade100);
        _showFailureDialog('Firestore Error', errMsg, currentUid, _adminUniId);
        return;
      } catch (err) {
        debugPrint('Unknown error while creating invite: $err');
        final errMsg = err.toString();
        Get.snackbar('Error', 'Failed to generate code: $errMsg',
            backgroundColor: Colors.red.shade100);
        _showFailureDialog('Unknown Error', errMsg, currentUid, _adminUniId);
        return;
      }

      setState(() {
        _generatedCode = code;
      });

      // Show success dialog with code
      _showCodeDialog(code, email);

    } finally {
      setState(() => _isGenerating = false);
    }
  }

  void _showFailureDialog(String title, String message, String? uid, String? uniId) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Row(children: [const Icon(Icons.error, color: Colors.red), const SizedBox(width: 8), Expanded(child: Text(title))]),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 12),
              Text('Admin UID: ${uid ?? 'unknown'}', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
              Text('Admin uniId: ${uniId ?? 'unknown'}', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
              const SizedBox(height: 12),
              const Text('Possible causes:\n• Permission denied (check Firestore rules)\n• Network issues\n• Invalid data format', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showCodeDialog(String code, String email) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            const SizedBox(width: 12),
            const Text('Invite Code Generated'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share this code with the faculty member:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200, width: 2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      code,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.blue),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      Get.snackbar('Copied', 'Code copied to clipboard',
                          backgroundColor: Colors.green.shade100,
                          duration: const Duration(seconds: 2));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Email: $email',
                      style: TextStyle(color: Colors.grey[700])),
                  const SizedBox(height: 4),
                  Text('Valid until: Never expires',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '📧 Send this code to the professor via email, WhatsApp, or any other method.',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetForm();
            },
            child: const Text('Generate Another'),
          ),
          TextButton.icon(
            icon: const Icon(Icons.email),
            label: const Text('Compose Email'),
            onPressed: () {
              _sendEmail(code, email);
              Navigator.pop(context);
              _resetForm();
            },
          ),
          ElevatedButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              Navigator.pop(context);
              Get.snackbar('Copied', 'Code copied! Share it with the faculty.',
                  backgroundColor: Colors.green.shade100);
              _resetForm();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Copy & Close'),
          ),
        ],
      ),
    );
  }

  void _resetForm() {
    _emailController.clear();
    _nameController.clear();
    _departmentController.clear();
    setState(() => _generatedCode = null);
  }

  Future<void> _sendEmail(String code, String toEmail) async {
    final subject = 'Faculty Invite Code';
    final body = 'Hello,\n\nYou have been invited to join our platform.\n\nInvite Code: $code\n\nUse this code to register as faculty.\n\nRegards,\nAdmin';

    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: toEmail,
      queryParameters: {
        'subject': subject,
        'body': body,
      },
    );

    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri, mode: LaunchMode.externalApplication);
      } else {
        Get.snackbar('Error', 'Could not open email client',
            backgroundColor: Colors.red.shade100);
      }
    } catch (e) {
      debugPrint('Email launcher error: $e');
      Get.snackbar('Error', 'Failed to launch email client: $e',
          backgroundColor: Colors.red.shade100);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Get.offAllNamed('/admin-dashboard');
            }
          },
        ),
        title: const Text('Generate Faculty Invite'),
        backgroundColor: const Color(0xFF5E5CE6),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF5E5CE6),
                    const Color(0xFF7B79EA),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(Icons.school, size: 64, color: Colors.white),
                  const SizedBox(height: 12),
                  const Text(
                    'Faculty Invite System',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Generate a secure code to invite faculty members',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // Form Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
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
                  const Text(
                    'Faculty Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Email Field (Required)
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Professor Email *',
                      hintText: 'professor@university.edu',
                      prefixIcon: const Icon(Icons.email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Name Field (Optional)
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Professor Name (Optional)',
                      hintText: 'Dr. John Smith',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Department Field (Optional)
                  TextField(
                    controller: _departmentController,
                    decoration: InputDecoration(
                      labelText: 'Department (Optional)',
                      hintText: 'Computer Science',
                      prefixIcon: const Icon(Icons.account_tree),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Generate Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isGenerating ? null : _generateInviteCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5E5CE6),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isGenerating
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Generate Invite Code',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'After generating, share the code with the faculty member. They will use it to create their account.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // View All Invites Button
            TextButton.icon(
              onPressed: () => Get.to(() => const ViewInvitesScreen()),
              icon: const Icon(Icons.list),
              label: const Text('View All Generated Invites'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF5E5CE6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _departmentController.dispose();
    super.dispose();
  }
}

// ============================================================================
// PART 2: VIEW ALL INVITES SCREEN
// ============================================================================
class ViewInvitesScreen extends StatefulWidget {
  const ViewInvitesScreen({super.key});

  @override
  State<ViewInvitesScreen> createState() => _ViewInvitesScreenState();
}

class _ViewInvitesScreenState extends State<ViewInvitesScreen> {
  String? _adminUniId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAdminUniId();
  }

  Future<void> _loadAdminUniId() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() {
          _adminUniId = null;
          _loading = false;
        });
        return;
      }
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final uni = doc.exists ? (doc.data()?['uniId'] as String?) : null;
      setState(() {
        _adminUniId = uni;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Failed to load admin uniId: $e');
      setState(() {
        _adminUniId = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text('All Faculty Invites'),
          backgroundColor: const Color(0xFF5E5CE6),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_adminUniId == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text('All Faculty Invites'),
          backgroundColor: const Color(0xFF5E5CE6),
        ),
        body: Center(
          child: Text(
            'Unable to determine your university. Please ensure you are signed in.',
            style: TextStyle(color: Colors.grey[700]),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final stream = FirebaseFirestore.instance
        .collection('invites')
        .where('uniId', isEqualTo: _adminUniId)
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('All Faculty Invites'),
        backgroundColor: const Color(0xFF5E5CE6),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No invites generated yet for your university',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              
              final code = data['code'] as String;
              final email = data['email'] as String;
              final isUsed = data['isUsed'] as bool? ?? false;
              final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
              final facultyName = data['facultyName'] as String? ?? 'Professor';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: isUsed
                        ? Colors.green.shade100
                        : Colors.blue.shade100,
                    child: Icon(
                      isUsed ? Icons.check_circle : Icons.pending,
                      color: isUsed ? Colors.green : Colors.blue,
                    ),
                  ),
                  title: Text(
                    code,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 1,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text('Name: $facultyName'),
                      Text('Email: $email'),
                      if (createdAt != null)
                        Text(
                          'Created: ${createdAt.day}/${createdAt.month}/${createdAt.year}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isUsed
                              ? Colors.green.withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isUsed ? 'Used' : 'Active',
                          style: TextStyle(
                            color: isUsed ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (!isUsed) ...[
                        const SizedBox(height: 8),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: code));
                            Get.snackbar('Copied', 'Code copied to clipboard',
                                backgroundColor: Colors.green.shade100,
                                duration: const Duration(seconds: 2));
                          },
                          tooltip: 'Copy code',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// PART 3: FIXED FACULTY INVITE SCREEN (Student/Faculty Side)
// ============================================================================
class FacultyInviteScreen extends StatefulWidget {
  const FacultyInviteScreen({super.key});

  @override
  State<FacultyInviteScreen> createState() => _FacultyInviteScreenState();
}

class _FacultyInviteScreenState extends State<FacultyInviteScreen> {
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _officeHoursController = TextEditingController(
      text: 'Mon-Fri: 9 AM - 5 PM');
  
  bool _isLoading = false;
  bool _codeVerified = false;
  String? _linkedEmail;
  String? _linkedUniId;
  String? _linkedDept;
  String? _suggestedName;
  DocumentReference? _inviteRef;

  // Step 1: Verify invite code
  Future<void> _verifyCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      Get.snackbar('Error', 'Please enter an invite code',
          backgroundColor: Colors.orange.shade100);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final QuerySnapshot result = await FirebaseFirestore.instance
          .collection('invites')
          .where('code', isEqualTo: code)
          .where('isUsed', isEqualTo: false)
          .limit(1)
          .get();

      if (result.docs.isEmpty) {
        Get.snackbar('Invalid Code', 'Code not found or already used',
            backgroundColor: Colors.red.shade100);
        setState(() => _isLoading = false);
        return;
      }

      // Success: Extract invite details
      final doc = result.docs.first;
      final data = doc.data() as Map<String, dynamic>;

      setState(() {
        _linkedEmail = data['email'] as String?;
        _linkedUniId = data['uniId'] as String?;
        _linkedDept = data['department'] as String?;
        _suggestedName = data['facultyName'] as String?;
        _inviteRef = doc.reference;
        _codeVerified = true;
        _isLoading = false;
        
        // Pre-fill name if available
        if (_suggestedName != null && _suggestedName!.isNotEmpty) {
          _nameController.text = _suggestedName!;
        }
      });

      Get.snackbar('Success', 'Code verified! Complete your profile',
          backgroundColor: Colors.green.shade100);
    } catch (e) {
      Get.snackbar('Error', 'Failed to verify code: $e',
          backgroundColor: Colors.red.shade100);
      setState(() => _isLoading = false);
    }
  }

  // Step 2: Register faculty account (FIXED: Create Auth User First)
  Future<void> _registerFaculty() async {
    final name = _nameController.text.trim();
    final password = _passwordController.text;
    final officeHours = _officeHoursController.text.trim();

    if (name.isEmpty) {
      Get.snackbar('Error', 'Please enter your name',
          backgroundColor: Colors.orange.shade100);
      return;
    }

    if (password.length < 6) {
      Get.snackbar('Error', 'Password must be at least 6 characters',
          backgroundColor: Colors.orange.shade100);
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_inviteRef == null || _linkedEmail == null) {
        throw Exception('Invalid invite data. Please verify code again.');
      }

      // Step A: Create Firebase Auth account FIRST
      // This establishes an authenticated user, allowing Firestore writes.
      UserCredential creds;
      try {
        creds = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _linkedEmail!,
          password: password,
        );
      } catch (authError) {
        // If auth fails (e.g. email exists), no changes were made to DB yet
        throw Exception('Account creation failed: ${authError.toString()}');
      }

      // Step B: Perform DB Updates (now authenticated)
      // We perform all writes in a batch/transaction to ensure consistency
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(_inviteRef!);
        if (!snap.exists) throw Exception('Invite not found');
        
        final isUsed = snap.get('isUsed') as bool? ?? false;
        if (isUsed) throw Exception('Invite already used');
        
        // 1. Mark invite as used
        tx.update(_inviteRef!, {
          'isUsed': true,
          'usedBy': creds.user!.uid,
          'reservedAt': FieldValue.serverTimestamp(),
        });

        // 2. Create user document
        final userRef = FirebaseFirestore.instance
            .collection('users')
            .doc(creds.user!.uid);
            
        tx.set(userRef, {
          'name': name,
          'email': _linkedEmail,
          'role': 'faculty',
          'dept': _linkedDept ?? 'Faculty',
          'title': 'Professor',
          'uniId': _linkedUniId ?? '',
          'isAvailable': true,
          'officeHours': officeHours,
          'imageUrl': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      // Success!
      Get.snackbar(
        'Success',
        'Account created! Redirecting to dashboard...',
        backgroundColor: Colors.green.shade100,
      );

      // Navigate to faculty dashboard
      await Future.delayed(const Duration(seconds: 1));
      Get.offAllNamed('/faculty-dashboard');

    } catch (e) {
      Get.snackbar('Error', 'Registration failed: $e',
          backgroundColor: Colors.red.shade100);
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2D2658),
      appBar: AppBar(
        title: const Text('Faculty Access'),
        backgroundColor: const Color(0xFF2D2658),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(Icons.school,
                      size: 80, color: const Color(0xFF546EDB)),
                  const SizedBox(height: 16),
                  Text(
                    _codeVerified
                        ? 'Complete Your Profile'
                        : 'Faculty Registration',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _codeVerified
                        ? 'Set up your faculty account'
                        : 'Enter your invite code to begin',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Form Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: !_codeVerified
                  ? _buildCodeVerificationStep()
                  : _buildRegistrationStep(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeVerificationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Enter Invite Code',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'You should have received this code from your admin',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _codeController,
          decoration: InputDecoration(
            labelText: 'Invite Code',
            hintText: 'e.g., FAC-12345',
            prefixIcon: const Icon(Icons.vpn_key),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey[50],
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF546EDB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Verify Code',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildRegistrationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Email Display
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Setting up for:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _linkedEmail ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.green.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Name Field
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: 'Full Name *',
            hintText: 'Dr. John Smith',
            prefixIcon: const Icon(Icons.person),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey[50],
          ),
        ),
        const SizedBox(height: 16),

        // Office Hours Field
        TextField(
          controller: _officeHoursController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Office Hours',
            hintText: 'Mon-Fri: 9 AM - 5 PM',
            prefixIcon: const Icon(Icons.access_time),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey[50],
          ),
        ),
        const SizedBox(height: 16),

        // Password Field
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Create Password *',
            hintText: 'Minimum 6 characters',
            prefixIcon: const Icon(Icons.lock),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey[50],
          ),
        ),
        const SizedBox(height: 24),

        // Register Button
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _registerFaculty,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Activate Account',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _officeHoursController.dispose();
    super.dispose();
  }
}

// ============================================================================
// PART 4: UPDATED STUDENT PORTAL (Firestore Integration Fix)
// ============================================================================
// This is the key fix for your student portal to load faculty properly

class StudentPortalFacultyController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final RxList<Map<String, dynamic>> allFaculty = <Map<String, dynamic>>[].obs;
  final RxBool isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    loadFacultyFromFirestore();
  }

  void loadFacultyFromFirestore() {
    isLoading.value = true;

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) {
      isLoading.value = false;
      Get.snackbar('Error', 'Not signed in', backgroundColor: Colors.red);
      return;
    }

    // First get the user's uniId
    _firestore.collection('users').doc(currentUid).get().then((userDoc) {
      final myUniId = userDoc.data()?['uniId'] as String?;
      if (myUniId == null) {
        isLoading.value = false;
        Get.snackbar('Error', 'Your account has no university assigned', backgroundColor: Colors.orange);
        return;
      }

      // Listen only to faculty within the same university
      _firestore
          .collection('users')
          .where('role', isEqualTo: 'faculty')
          .where('uniId', isEqualTo: myUniId)
          .snapshots()
          .listen((snapshot) {
        allFaculty.value = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'name': data['name'] ?? 'Professor',
            'email': data['email'] ?? '',
            'dept': data['dept'] ?? 'Faculty',
            'title': data['title'] ?? '',
            'isAvailable': data['isAvailable'] ?? false,
            'officeHours': data['officeHours'] ?? 'Not specified',
            'imageUrl': data['imageUrl'] ?? '',
          };
        }).toList();

        isLoading.value = false;
        debugPrint('✅ Loaded ${allFaculty.length} faculty members for uni=$myUniId');
      }, onError: (error) {
        isLoading.value = false;
        Get.snackbar(
          'Error',
          'Failed to load faculty: $error',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      });
    }).catchError((e) {
      isLoading.value = false;
      Get.snackbar('Error', 'Failed to determine your university: $e', backgroundColor: Colors.red);
    });
  }
}

// ============================================================================
// PART 5: FIRESTORE RULES (Copy these to your Firebase Console)
// ============================================================================

/*
COPY THESE FIRESTORE SECURITY RULES TO FIREBASE CONSOLE:
Go to: Firebase Console → Firestore Database → Rules

rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Allow anyone to read users with role='faculty' (for student portal)
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
      allow create: if request.auth != null;
    }
    
    // Invites collection - Admin can create, anyone can read their own
    match /invites/{inviteId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update: if request.auth != null;
    }
    
    // Appointments - Students and Faculty can read/write their own
    match /appointments/{appointmentId} {
      allow read: if request.auth != null && 
        (resource.data.studentId == request.auth.uid || 
         resource.data.facultyId == request.auth.uid ||
         resource.data.profId == request.auth.uid);
      allow create: if request.auth != null;
      allow update: if request.auth != null && 
        (resource.data.studentId == request.auth.uid || 
         resource.data.facultyId == request.auth.uid ||
         resource.data.profId == request.auth.uid);
    }
    
    // Universities - Read-only for everyone
    match /universities/{uniId} {
      allow read: if true;
      match /{document=**} {
        allow read: if true;
      }
    }
  }
}
*/

// ============================================================================
// PART 6: COMPLETE INTEGRATION GUIDE
// ============================================================================

/*
🔧 SETUP INSTRUCTIONS:

1️⃣ ADD THESE FILES TO YOUR PROJECT:
   - admin_faculty_invite_screen.dart (for admins to generate codes)
   - faculty_invite_screen.dart (for faculty to register with code)

2️⃣ UPDATE YOUR NAVIGATION ROUTES:
   Add these to your GetX routing:
   
   GetPage(name: '/admin-generate-invite', page: () => AdminFacultyInviteScreen()),
   GetPage(name: '/faculty-invite', page: () => FacultyInviteScreen()),
   GetPage(name: '/faculty-dashboard', page: () => FacultyDashboardScreen()),

3️⃣ UPDATE FIRESTORE RULES:
   - Copy the rules above to Firebase Console → Firestore → Rules
   - Click "Publish" to apply changes

4️⃣ TEST THE FLOW:
   ADMIN SIDE:
   a) Login as admin
   b) Navigate to AdminFacultyInviteScreen
   c) Enter professor email: professor@university.edu
   d) Click "Generate Invite Code"
   e) Copy code (e.g., FAC-12345)
   
   FACULTY SIDE:
   f) Go to FacultyInviteScreen (from login page)
   g) Enter code: FAC-12345
   h) Fill in name and password
   i) Click "Activate Account"
   j) Redirects to Faculty Dashboard
   
   STUDENT SIDE:
   k) Login as student
   l) Open student portal
   m) See all faculty members (including newly registered)
   n) Book appointment

5️⃣ FIRESTORE COLLECTION STRUCTURE:

   /invites/{inviteId}
   - code: "FAC-12345"
   - email: "professor@university.edu"
   - facultyName: "Dr. Smith"
   - department: "Computer Science"
   - uniId: "uni123"
   - isUsed: false
   - createdAt: timestamp
   - createdBy: "adminUID"
   
   /users/{facultyId}
   - name: "Dr. John Smith"
   - email: "professor@university.edu"
   - role: "faculty"
   - dept: "Computer Science"
   - title: "Professor"
   - isAvailable: true
   - officeHours: "Mon-Fri: 9 AM - 5 PM"
   - uniId: "uni123"
   
   /appointments/{appointmentId}
   - studentId: "studentUID"
   - facultyId: "facultyUID" (or profId)
   - studentName: "John Doe"
   - facultyName: "Dr. Smith"
   - requestDate: timestamp
   - requestTime: "10:00 AM"
   - reason: "Project discussion"
   - status: "pending"

6️⃣ COMMON ISSUES & FIXES:

   ❌ "Permission denied" error:
   ✅ Update Firestore rules (see above)
   
   ❌ Faculty not showing in student portal:
   ✅ Ensure faculty has role='faculty' in Firestore
   ✅ Check facultyId vs profId field naming
   
   ❌ Code not verifying:
   ✅ Check code is uppercase (FAC-12345)
   ✅ Ensure isUsed=false in invite document
   
   ❌ Appointments not saving:
   ✅ Use 'facultyId' or 'profId' consistently
   ✅ Update both student portal and faculty dashboard

7️⃣ UPDATING EXISTING CODE:

   In your student booking portal (student_portal.dart):
   - Change 'profId' to 'facultyId' (or vice versa, but be consistent)
   
   In faculty_dashboard.dart:
   - Update queries from 'profId' to 'facultyId' if needed
   
   Example fix for student portal:
   ```dart
   // When creating appointment:
   await FirebaseFirestore.instance.collection('appointments').add({
     'studentId': uid,
     'facultyId': selectedFaculty.id, // ← Use 'facultyId' consistently
     'studentName': studentName,
     'facultyName': selectedFaculty.name,
     // ... other fields
   });*/