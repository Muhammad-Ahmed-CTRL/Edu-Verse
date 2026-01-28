// File: lib/modules/placement/screens/student_placement_screen.dart
// Updated: Base64 Resume Upload (No Storage Bucket required) & Size Limit Notifications

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io' show File;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:math';
import 'dart:convert'; // Required for base64Encode
import 'dart:typed_data';

// --- IMPORT GLOBAL THEME ---
import 'package:reclaimify/theme_colors.dart';

// ==================== MODELS ====================

class StudentUser {
  final String uid;
  final String email;
  final String name;
  final String university;
  final String role;
  final String? photoUrl;
  final String? resumeUrl;

  StudentUser({
    required this.uid,
    required this.email,
    required this.name,
    required this.university,
    required this.role,
    this.photoUrl,
    this.resumeUrl,
  });

  factory StudentUser.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return StudentUser(
      uid: doc.id,
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      university: data['university'] ?? '',
      role: data['role'] ?? 'student',
      photoUrl: data['photoUrl'],
      resumeUrl: data['resumeUrl'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'university': university,
      'role': role,
      'photoUrl': photoUrl,
      'resumeUrl': resumeUrl,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

class JobOpportunity {
  final String id;
  final String title;
  final String company;
  final String salary;
  final String description;
  final String requirements;
  final String targetUniversity;
  final bool isRemote;
  final String location;
  final String recruiterId;
  final String recruiterEmail;
  final int applicantsCount;
  final DateTime? createdAt;
  final bool isActive;

  JobOpportunity({
    required this.id,
    required this.title,
    required this.company,
    required this.salary,
    required this.description,
    required this.requirements,
    required this.targetUniversity,
    required this.isRemote,
    required this.location,
    required this.recruiterId,
    required this.recruiterEmail,
    this.applicantsCount = 0,
    this.createdAt,
    this.isActive = true,
  });

  factory JobOpportunity.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return JobOpportunity(
      id: doc.id,
      title: data['title'] ?? '',
      company: data['company'] ?? '',
      salary: data['salary'] ?? '',
      description: data['description'] ?? '',
      requirements: data['requirements'] ?? '',
      targetUniversity: data['targetUniversity'] ?? 'All Universities',
      isRemote: data['isRemote'] ?? false,
      location: data['location'] ?? '',
      recruiterId: data['recruiterId'] ?? '',
      recruiterEmail: data['recruiterEmail'] ?? '',
      applicantsCount: data['applicantsCount'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      isActive: data['isActive'] ?? true,
    );
  }

  String get companyLogo => company.isNotEmpty ? company[0].toUpperCase() : 'C';

  int get matchPercentage => 95;
}

class JobApplication {
  final String? id;
  final String jobId;
  final String studentId;
  final String studentName;
  final String studentEmail;
  final String university;
  final String recruiterId;
  final String resumeUrl;
  final String status;
  final DateTime? appliedAt;

  JobApplication({
    this.id,
    required this.jobId,
    required this.studentId,
    required this.studentName,
    required this.studentEmail,
    required this.university,
    required this.recruiterId,
    required this.resumeUrl,
    this.status = 'pending',
    this.appliedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'jobId': jobId,
      'studentId': studentId,
      'studentName': studentName,
      'studentEmail': studentEmail,
      'university': university,
      'recruiterId': recruiterId,
      'resumeUrl': resumeUrl,
      'status': status,
      'appliedAt': FieldValue.serverTimestamp(),
    };
  }
}

// ==================== AUTHENTICATION SERVICE ====================

class StudentAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<Map<String, dynamic>> signIn(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(result.user!.uid).get();

      if (!userDoc.exists) {
        await _auth.signOut();
        return {
          'success': false,
          'message': 'User not found. Please contact admin.'
        };
      }

      Map userData = userDoc.data() as Map<String, dynamic>;
      if (userData['role'] != 'student') {
        await _auth.signOut();
        return {
          'success': false,
          'message': 'Access denied. This portal is for students only.'
        };
      }

      return {'success': true, 'user': result.user};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'message': _getErrorMessage(e.code)};
    } catch (e) {
      return {
        'success': false,
        'message': 'An error occurred: ${e.toString()}'
      };
    }
  }

  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String name,
    required String university,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await _firestore.collection('users').doc(result.user!.uid).set({
        'email': email,
        'name': name,
        'university': university,
        'role': 'student',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await result.user!.updateDisplayName(name);

      return {'success': true, 'user': result.user};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'message': _getErrorMessage(e.code)};
    } catch (e) {
      return {
        'success': false,
        'message': 'An error occurred: ${e.toString()}'
      };
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<StudentUser?> getStudentData(String uid) async {
    try {
      DocumentSnapshot doc =
          await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return StudentUser.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('Error getting student data: $e');
      return null;
    }
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      case 'invalid-email':
        return 'Invalid email address.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}

// ==================== FIRESTORE SERVICE ====================

class StudentFirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<JobOpportunity>> getFilteredJobs(String studentUniversity) {
    return _firestore
        .collection('jobs')
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => JobOpportunity.fromFirestore(doc))
          .where((job) {
        return job.targetUniversity == 'All Universities' ||
            job.targetUniversity == studentUniversity;
      }).toList();
    });
  }

  Future<Map<String, dynamic>> applyForJob(JobApplication application) async {
    try {
      print(
          'DEBUG: Checking existing applications for jobId: ${application.jobId}, studentId: ${application.studentId}');

      QuerySnapshot existingApplication = await _firestore
          .collection('applications')
          .where('jobId', isEqualTo: application.jobId)
          .where('studentId', isEqualTo: application.studentId)
          .get();

      if (existingApplication.docs.isNotEmpty) {
        return {
          'success': false,
          'message': 'You have already applied for this job.'
        };
      }

      // Check if resumeUrl is a huge base64 string and warn log (optional)
      // We still store it in applications collection.
      
      await _firestore.collection('applications').add(application.toMap());

      await _firestore
          .collection('jobs')
          .doc(application.jobId)
          .update({'applicantsCount': FieldValue.increment(1)});

      return {
        'success': true,
        'message': 'Application submitted successfully!'
      };
    } catch (e) {
      print('DEBUG ERROR: $e');
      return {'success': false, 'message': 'Error applying: ${e.toString()}'};
    }
  }

  Future<bool> hasApplied(String jobId, String studentId) async {
    try {
      QuerySnapshot result = await _firestore
          .collection('applications')
          .where('jobId', isEqualTo: jobId)
          .where('studentId', isEqualTo: studentId)
          .get();
      return result.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Stream<QuerySnapshot> getMyApplications(String studentId) {
    return _firestore
        .collection('applications')
        .where('studentId', isEqualTo: studentId)
        .orderBy('appliedAt', descending: true)
        .snapshots();
  }

  Future<void> bookmarkJob(String studentId, String jobId) async {
    await _firestore
        .collection('users')
        .doc(studentId)
        .collection('bookmarks')
        .doc(jobId)
        .set({'timestamp': FieldValue.serverTimestamp()});
  }

  Future<void> removeBookmark(String studentId, String jobId) async {
    await _firestore
        .collection('users')
        .doc(studentId)
        .collection('bookmarks')
        .doc(jobId)
        .delete();
  }

  Future<bool> isBookmarked(String studentId, String jobId) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(studentId)
          .collection('bookmarks')
          .doc(jobId)
          .get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }
}

// ==================== STUDENT LOGIN SCREEN ====================

class StudentLoginScreen extends StatefulWidget {
  const StudentLoginScreen({Key? key}) : super(key: key);

  @override
  State<StudentLoginScreen> createState() => _StudentLoginScreenState();
}

class _StudentLoginScreenState extends State<StudentLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _authService = StudentAuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isSignUp = false;
  String _selectedUniversity = 'Air University';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    Map<String, dynamic> result;

    if (_isSignUp) {
      result = await _authService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
        university: _selectedUniversity,
      );
    } else {
      result = await _authService.signIn(
        _emailController.text.trim(),
        _passwordController.text,
      );
    }

    setState(() => _isLoading = false);

    if (result['success']) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const StudentPlacementScreen(),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.white.withOpacity(0.1) : kWhiteColor;
    final textColor = getAppTextColor(context);
    final inputFillColor = isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF5F5F7);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kDarkBackgroundColor, kPrimaryColor],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.school,
                      size: 60,
                      color: kPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _isSignUp ? 'Student Registration' : 'Student Portal',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isSignUp
                        ? 'Create your account to find opportunities'
                        : 'Sign in to explore internships & placements',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          if (_isSignUp) ...[
                            TextFormField(
                              controller: _nameController,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                labelText: 'Full Name',
                                prefixIcon: const Icon(Icons.person_outline),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: inputFillColor,
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: _selectedUniversity,
                              dropdownColor: isDark ? kDarkBackgroundColor : kWhiteColor,
                              decoration: InputDecoration(
                                labelText: 'University',
                                prefixIcon: const Icon(Icons.school_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: inputFillColor,
                              ),
                              items: [
                                'Air University',
                                'NUST',
                                'Bahria University',
                                'FAST University',
                                'COMSATS',
                              ].map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value, style: TextStyle(color: textColor)),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                setState(() {
                                  _selectedUniversity = newValue!;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: TextStyle(color: textColor),
                            decoration: InputDecoration(
                              labelText: 'Email',
                              prefixIcon: const Icon(Icons.email_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: inputFillColor,
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!value.contains('@')) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: TextStyle(color: textColor),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: inputFillColor,
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your password';
                              }
                              if (value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleAuth,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimaryColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      _isSignUp ? 'Create Account' : 'Sign In',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _isSignUp = !_isSignUp;
                              });
                            },
                            child: Text(
                              _isSignUp
                                  ? 'Already have an account? Sign In'
                                  : 'New student? Create Account',
                              style: const TextStyle(
                                color: kPrimaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== MAIN STUDENT SCREEN ====================

class StudentPlacementScreen extends StatefulWidget {
  const StudentPlacementScreen({Key? key}) : super(key: key);

  @override
  State<StudentPlacementScreen> createState() => _StudentPlacementScreenState();
}

class _StudentPlacementScreenState extends State<StudentPlacementScreen> {
  final _authService = StudentAuthService();
  final _firestoreService = StudentFirestoreService();
  StudentUser? _studentData;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadStudentData();
  }

  Future<void> _loadStudentData() async {
    final user = _authService.currentUser;
    if (user != null) {
      final data = await _authService.getStudentData(user.uid);
      setState(() {
        _studentData = data;
      });
    }
  }

  // -------------------------------------------------------------
  // REVISED UPLOAD HANDLER: PURE FIRESTORE (BASE64) NO STORAGE
  // -------------------------------------------------------------
  Future<void> _uploadResumeHandler() async {
    var user = _authService.currentUser;
    if (user == null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const StudentLoginScreen()),
      );
      if (!mounted) return;
      user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in required to upload resume')),
        );
        return;
      }
    }

    final String uid = user!.uid;

    try {
      // 1. Pick File - Force withData: true to get bytes for Base64 conversion
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true, 
      );

      if (result == null || result.files.isEmpty) return;

      final picked = result.files.first;
      final int sizeBytes = picked.size;
      final String name = picked.name;
      final String ext = (picked.extension ?? name.split('.').last).toLowerCase();

      // 2. Validate PDF format
      if (ext != 'pdf') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(
             content: Text('Invalid format. Only PDF files are allowed.'),
             backgroundColor: Colors.red,
           ),
        );
        return;
      }

      // 3. SIZE CHECK Logic (Free Tier / Firestore Doc Limit)
      // Firestore doc limit is 1MB. Base64 encoding adds ~33% size.
      // 700KB file -> ~930KB string. Safety margin: 700KB.
      const int maxFirestoreBytes = 700 * 1024; // 700 KB

      if (sizeBytes > maxFirestoreBytes) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (c) {
             final isDark = Theme.of(context).brightness == Brightness.dark;
             // Ensure dialog text is visible in dark/light mode
             return AlertDialog(
              backgroundColor: isDark ? kDarkBackgroundColor : Colors.white,
              title: Text(
                'File too large', 
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
              content: Text(
                'Due to free tier limitations, resumes must be under 700KB to be stored directly in the database.\n\nYour file: ${_formatBytes(sizeBytes)}',
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c), 
                  child: const Text('OK', style: TextStyle(color: kPrimaryColor)),
                ),
              ],
            );
          },
        );
        return;
      }

      // 4. Confirmation Dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? kDarkBackgroundColor : Colors.white,
            title: Text(
              'Upload Resume',
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'File: $name',
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                ),
                const SizedBox(height: 6),
                Text(
                  'Size: ${_formatBytes(sizeBytes)}',
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                ),
                const SizedBox(height: 10),
                Text(
                  'This will be saved directly to the database.',
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.grey : Colors.grey[600]),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Save', style: TextStyle(color: kPrimaryColor)),
              ),
            ],
          );
        },
      );

      if (confirmed != true) return;
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saving resume...')),
      );

      // 5. Convert to Base64 (The Core Logic for No-Storage Upload)
      Uint8List? fileBytes = picked.bytes;
      
      // Fallback: If bytes are null (native sometimes), read from path
      if (fileBytes == null && picked.path != null) {
        fileBytes = await File(picked.path!).readAsBytes();
      }

      if (fileBytes == null) {
         throw Exception("Could not read file data. Please try again.");
      }

      final String base64Data = base64Encode(fileBytes);
      final String dataUri = 'data:application/pdf;base64,$base64Data';

      // 6. Update Firestore User Document
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'resumeUrl': dataUri, // Saving the large string directly to Firestore
        'resumeName': name,
        'resumeUpdatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      await _loadStudentData();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Resume saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      print("Resume Upload Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving resume: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatBytes(int bytes, [int decimals = 2]) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    final i = (log(bytes) / log(1024)).floor();
    final size = bytes / pow(1024, i);
    return '${size.toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  void _showComingSoon(BuildContext context, String title) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: const Text(
            'This feature is under development and will be available soon.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check Theme Mode
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = getAppBackgroundColor(context);
    final cardColor = isDark ? Colors.white.withOpacity(0.1) : kWhiteColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: _currentIndex == 0
          ? _buildHomeTab()
          : _currentIndex == 1
              ? _buildApplicationsTab()
              : _buildProfileTab(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: kPrimaryColor,
        unselectedItemColor: isDark ? Colors.white70 : Colors.grey,
        backgroundColor: cardColor,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.work_outline),
            activeIcon: Icon(Icons.work),
            label: 'Jobs',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            activeIcon: Icon(Icons.assignment),
            label: 'Applications',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    final textColor = getAppTextColor(context);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 170,
          floating: false,
          pinned: true,
          backgroundColor: kPrimaryColor,
          elevation: 0,
          title: const Text(
            'Placement & Internships',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          centerTitle: true,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [kDarkBackgroundColor, kPrimaryColor],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                        SizedBox(height: 48),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: TextField(
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Search jobs...',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 14,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.search,
                                    color: Colors.white.withOpacity(0.7),
                                  ),
                                  border: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            height: 50,
                            width: 50,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.tune,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          actions: [
            if (_studentData != null)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white,
                  child: Text(
                    _studentData!.name[0].toUpperCase(),
                    style: const TextStyle(
                      color: kPrimaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
          ],
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Available Opportunities',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.verified,
                            size: 14,
                            color: kPrimaryColor,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Verified',
                            style: TextStyle(
                              fontSize: 11,
                              color: kPrimaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              StreamBuilder<List<JobOpportunity>>(
                stream: _studentData != null
                    ? _firestoreService
                        .getFilteredJobs(_studentData!.university)
                    : null,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'Error: ${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red[700]),
                        ),
                      ),
                    );
                  }

                  final jobs = snapshot.data ?? [];

                  if (jobs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Icon(Icons.work_off_outlined,
                                size: 80, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('No opportunities available',
                                style: TextStyle(color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: jobs.length,
                    itemBuilder: (context, index) {
                      return StudentJobCard(
                        job: jobs[index],
                        studentId: _authService.currentUser?.uid,
                        onTap: () => _showJobDetails(jobs[index]),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildApplicationsTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.white.withOpacity(0.1) : kWhiteColor;
    final textColor = getAppTextColor(context);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: kPrimaryColor,
          title: const Text('My Applications', style: TextStyle(color: Colors.white)),
        ),
        SliverToBoxAdapter(
          child: _authService.currentUser == null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 72,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Sign in to view your applications',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                )
              : StreamBuilder<QuerySnapshot>(
                  stream: _firestoreService.getMyApplications(
                    _authService.currentUser!.uid,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'Error: ${snapshot.error}',
                            textAlign: TextAlign.center,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.red[700]),
                          ),
                        ),
                      );
                    }

                    final applications = snapshot.data?.docs ?? [];

                    if (applications.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                size: 80,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No applications yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Start applying to jobs!',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: applications.length,
                      itemBuilder: (context, index) {
                        final app =
                            applications[index].data() as Map<String, dynamic>;
                        return FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('jobs')
                              .doc(app['jobId'])
                              .get(),
                          builder: (context, jobSnapshot) {
                            if (!jobSnapshot.hasData) {
                              return const SizedBox.shrink();
                            }

                            final job =
                                JobOpportunity.fromFirestore(jobSnapshot.data!);

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              color: cardColor,
                              child: ListTile(
                                leading: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: kPrimaryColor,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.work_outline,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                title: Text(job.title, style: TextStyle(color: textColor)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(job.company, style: TextStyle(color: textColor.withOpacity(0.7))),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Applied: ${_formatDate(app['appliedAt'])}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: _buildStatusChip(app['status']),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProfileTab() {
    final textColor = getAppTextColor(context);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [kDarkBackgroundColor, kPrimaryColor],
              ),
            ),
            child: FlexibleSpaceBar(
              background: SafeArea(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: 48),
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.white,
                      child: Text(
                        _studentData?.name[0].toUpperCase() ?? 'S',
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: kPrimaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _studentData?.name ?? 'Student',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _studentData?.university ?? '',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                      ),
                    ),
                  ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.of(context).padding.bottom + 8),
            child: Column(
              children: [
                if (_studentData?.resumeUrl != null &&
                    _studentData!.resumeUrl!.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2E7D32)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: Color(0xFF2E7D32)),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Resume uploaded successfully',
                            style: TextStyle(
                              color: Color(0xFF2E7D32),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                _buildProfileOption(
                  Icons.description_outlined,
                  _studentData?.resumeUrl != null &&
                          _studentData!.resumeUrl!.isNotEmpty
                      ? 'Update Resume'
                      : 'Upload Resume',
                  () => _uploadResumeHandler(),
                ),
                _buildProfileOption(
                  Icons.notifications_outlined,
                  'Notifications',
                  () => _showComingSoon(context, 'Notifications'),
                ),
                _buildProfileOption(
                  Icons.help_outline,
                  'Help & Support',
                  () => _showComingSoon(context, 'Help & Support'),
                ),
                SizedBox(height: 20 + MediaQuery.of(context).padding.bottom + 8),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileOption(IconData icon, String title, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.white.withOpacity(0.1) : kWhiteColor;
    final textColor = getAppTextColor(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: cardColor, 
      child: ListTile(
        leading: Icon(icon, color: kPrimaryColor),
        title: Text(title, style: TextStyle(color: textColor)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    switch (status) {
      case 'accepted':
        color = Colors.green;
        break;
      case 'rejected':
        color = Colors.red;
        break;
      default:
        color = Colors.orange;
    }

    return Chip(
      label: Text(
        status.toUpperCase(),
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
      backgroundColor: color,
      padding: EdgeInsets.zero,
    );
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Recently';
    try {
      DateTime date = (timestamp as Timestamp).toDate();
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Recently';
    }
  }

  void _showJobDetails(JobOpportunity job) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => JobDetailsScreen(
          job: job,
          studentData: _studentData,
        ),
      ),
    );
  }
}

// ==================== STUDENT JOB CARD ====================

class StudentJobCard extends StatelessWidget {
  final JobOpportunity job;
  final String? studentId;
  final VoidCallback onTap;

  const StudentJobCard({
    Key? key,
    required this.job,
    this.studentId,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.white.withOpacity(0.1) : kWhiteColor;
    
    final textColor = getAppTextColor(context);
    final secondaryTextColor = isDark ? Colors.white70 : Colors.grey[600];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  job.companyLogo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    job.company,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: secondaryTextColor,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: secondaryTextColor,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          job.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryTextColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.grey[100],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          job.isRemote ? 'Remote' : 'On-site',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            job.salary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${job.matchPercentage}%',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Builder(builder: (context) {
              if (studentId == null || studentId!.isEmpty) {
                return IconButton(
                  onPressed: null,
                  icon: Icon(
                    Icons.bookmark_border,
                    color: Colors.grey[300],
                    size: 22,
                  ),
                );
              }

              return FutureBuilder<bool>(
                future:
                    StudentFirestoreService().isBookmarked(studentId!, job.id),
                builder: (context, snapshot) {
                  final isBookmarked = snapshot.data ?? false;
                  return IconButton(
                    onPressed: () async {
                      if (isBookmarked) {
                        await StudentFirestoreService()
                            .removeBookmark(studentId!, job.id);
                      } else {
                        await StudentFirestoreService()
                            .bookmarkJob(studentId!, job.id);
                      }
                      (context as Element).markNeedsBuild();
                    },
                    icon: Icon(
                      isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                      color: isBookmarked
                          ? kPrimaryColor
                          : Colors.grey[400],
                      size: 22,
                    ),
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ==================== JOB DETAILS SCREEN ====================

class JobDetailsScreen extends StatefulWidget {
  final JobOpportunity job;
  final StudentUser? studentData;

  const JobDetailsScreen({
    Key? key,
    required this.job,
    this.studentData,
  }) : super(key: key);

  @override
  State<JobDetailsScreen> createState() => _JobDetailsScreenState();
}

class _JobDetailsScreenState extends State<JobDetailsScreen> {
  final _firestoreService = StudentFirestoreService();
  bool _hasApplied = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkApplicationStatus();
  }

  Future<void> _checkApplicationStatus() async {
    String? studentId = widget.studentData?.uid;
    if (studentId == null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _hasApplied = false;
          _isLoading = false;
        });
        return;
      }
      studentId = user.uid;
    }

    final applied = await _firestoreService.hasApplied(
      widget.job.id,
      studentId,
    );
    setState(() {
      _hasApplied = applied;
      _isLoading = false;
    });
  }

  Future<void> _applyForJob() async {
    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const StudentLoginScreen()),
      );
      if (!mounted) return;
      setState(() => _isLoading = true);
      final newUser = FirebaseAuth.instance.currentUser;
      if (newUser == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must sign in to apply')),
        );
        return;
      }
    }

    final student = await StudentAuthService().getStudentData(user!.uid);
    if (student == null) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student profile not found')),
      );
      return;
    }

    if (student.resumeUrl == null || student.resumeUrl!.isEmpty) {
      setState(() => _isLoading = false);

      final shouldUpload = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Resume Required'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined,
                  size: 64, color: kPrimaryColor),
              SizedBox(height: 16),
              Text(
                'You need to upload your resume before applying to jobs.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
              ),
              child: const Text('Upload Resume', style: TextStyle(color: Colors.white),),
            ),
          ],
        ),
      );

      if (shouldUpload == true) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please go to Profile tab to upload your resume'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final application = JobApplication(
      jobId: widget.job.id,
      studentId: student.uid,
      studentName: student.name,
      studentEmail: student.email,
      university: student.university,
      recruiterId: widget.job.recruiterId,
      resumeUrl: student.resumeUrl!,
    );

    final result = await _firestoreService.applyForJob(application);

    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['message']),
        backgroundColor: result['success'] ? Colors.green : Colors.red,
      ),
    );

    if (result['success']) {
      setState(() => _hasApplied = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = getAppBackgroundColor(context);
    final cardColor = isDark ? Colors.white.withOpacity(0.1) : kWhiteColor;
    final textColor = getAppTextColor(context);
    final secondaryTextColor = isDark ? Colors.white70 : Colors.grey[700];

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [kDarkBackgroundColor, kPrimaryColor],
                ),
              ),
              child: FlexibleSpaceBar(
                background: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(height: 48),
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            widget.job.companyLogo,
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: kPrimaryColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.job.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.job.company,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildInfoChip(
                        Icons.attach_money,
                        widget.job.salary,
                      ),
                      _buildInfoChip(
                        Icons.location_on_outlined,
                        widget.job.location,
                      ),
                      _buildInfoChip(
                        widget.job.isRemote
                            ? Icons.home_work_outlined
                            : Icons.business_outlined,
                        widget.job.isRemote ? 'Remote' : 'On-site',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Description',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.job.description,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Requirements',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.job.requirements,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: secondaryTextColor,
                    ),
                  ),
                  SizedBox(height: 100 + MediaQuery.of(context).padding.bottom),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _hasApplied || _isLoading ? null : _applyForJob,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _hasApplied ? Colors.grey : kPrimaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      _hasApplied ? 'Already Applied' : 'Apply Now',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: kPrimaryColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}