import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'shared.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'notifications.dart';

// --- FIXED IMPORT PATH HERE ---
import 'timetable/FACULTY/faculty_invite_screen.dart';

// ==========================================
// AUTH SERVICE (Logic)
// ==========================================

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  AuthService._internal();

  User? get currentUser => _auth.currentUser;

  Future<User?> logIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return _auth.currentUser;
    } on FirebaseAuthException catch (e) {
      MySnackBar().mySnackBar(
          header: "Login Failed",
          content: e.message ?? "Error",
          bgColor: Colors.red.shade100);
      rethrow;
    }
  }

  // --- ADMIN: GENERATE FACULTY INVITE CODE ---
  Future<String> generateFacultyInvite({
    required String facultyEmail, 
    required String uniId,
    String? deptId
  }) async {
    try {
      // Generate a random code: FAC + last 5 digits of timestamp
      String code = "FAC-${DateTime.now().millisecondsSinceEpoch.toString().substring(8, 13)}";
      
      await FirebaseFirestore.instance.collection('invites').add({
        'code': code,
        'email': facultyEmail,
        'uniId': uniId,
        'departmentId': deptId ?? '',
        'isUsed': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': _auth.currentUser?.uid, // Added for auditing
      });
      
      return code;
    } catch (e) {
      debugPrint("Error creating invite: $e");
      rethrow;
    }
  }

  Future<User?> createUser(
      {required String email,
      required String password,
      required String username,
      String? uniId,
      String? departmentId,
      String? sectionId,
      String? shift,
      String? semester,
      String? uniUniqueId}) async {
    try {
      await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection("users").doc(uid).set({
          'email': email,
          'name': username,
          'uniId': uniId ?? '',
          'departmentId': departmentId ?? '',
          'sectionId': sectionId ?? '',
          'shift': shift ?? '',
          'semester': semester ?? '',
          'uniUniqueId': uniUniqueId ?? '',
          'role': 'student',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      return _auth.currentUser;
    } on FirebaseAuthException catch (e, s) {
      debugPrint('FirebaseAuthException in createUser: code=${e.code} message=${e.message}');
      debugPrint('Stack: $s');
      MySnackBar().mySnackBar(
          header: "Registration Failed",
          content: '${e.code}: ${e.message ?? 'No message'}',
          bgColor: Colors.red.shade100);
      rethrow;
    } catch (e, s) {
      debugPrint('Unexpected error in createUser: $e');
      debugPrint('Stack: $s');
      MySnackBar().mySnackBar(
          header: "Registration Failed",
          content: e.toString(),
          bgColor: Colors.red.shade100);
      rethrow;
    }
  }

  Future<void> sendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        MySnackBar().mySnackBar(
            header: "Error",
            content: "No signed-in user",
            bgColor: Colors.red.shade100);
        return;
      }
      await user.sendEmailVerification();
      MySnackBar().mySnackBar(
          header: "Email Sent",
          content: "Verification email sent. Check your inbox (or spam)",
          bgColor: Colors.green.shade100);
      debugPrint('Verification email sent to ${user.email}');
    } on FirebaseAuthException catch (e, s) {
      debugPrint('Failed to send verification email: ${e.code} ${e.message}');
      debugPrint('Stack: $s');
      MySnackBar().mySnackBar(
          header: "Error sending email",
          content: '${e.code}: ${e.message ?? ""}',
          bgColor: Colors.red.shade100);
      rethrow;
    } catch (e, s) {
      debugPrint('Unexpected error sending verification email: $e');
      debugPrint('Stack: $s');
      MySnackBar().mySnackBar(
          header: "Error", content: e.toString(), bgColor: Colors.red.shade100);
      rethrow;
    }
  }

  Future<bool> checkEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    final freshUser = _auth.currentUser;
    return freshUser?.emailVerified ?? false;
  }

  Future<void> logOut() async {
    await _auth.signOut();
  }

  Future<String> getName() async {
    if (currentUser == null) return "";
    var doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser!.uid)
        .get();
    if (doc.exists) return doc['name'] ?? "";
    return "";
  }

  Future<String> getPhone(String uid) async {
    var doc = await FirebaseFirestore.instance
        .collection('phoneNumbers')
        .where('uid', isEqualTo: uid)
        .limit(1)
        .get();
    if (doc.docs.isNotEmpty) return doc.docs.first['phoneNumber'];
    return "";
  }

  Future<List<Map<String, dynamic>>> fetchUniversities() async {
    var snap =
        await FirebaseFirestore.instance.collection('universities').get();
    return snap.docs
        .map((d) =>
            <String, dynamic>{'id': d.id, 'name': d.data()['name'] ?? d.id})
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchUniversitiesDetailed() async {
    var snap =
        await FirebaseFirestore.instance.collection('universities').get();
    return snap.docs.map((d) {
      final data = d.data();
      return {
        'id': d.id,
        'name': data['name'] ?? d.id,
        'domains': List<String>.from(data['domains'] ?? []),
        'require_allowed_ids': data['require_allowed_ids'] ?? false,
      };
    }).toList();
  }

  Future<Map<String, dynamic>?> getUniversityByEmail(String email) async {
    if (email.isEmpty || !email.contains('@')) return null;
    final domain = email.split('@').last.toLowerCase();
    final unis = await fetchUniversitiesDetailed();
    for (final u in unis) {
      final domains = (u['domains'] as List<String>?) ?? [];
      if (domains.map((s) => s.toLowerCase()).contains(domain)) return u;
    }
    for (final u in unis) {
      final domains = (u['domains'] as List<String>?) ?? [];
      for (final d in domains) {
        final ld = d.toLowerCase();
        if (domain.endsWith(ld)) return u;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> getUniversityByUniqueId(
      String uniUniqueId) async {
    if (uniUniqueId.isEmpty) return null;
    final unis = await fetchUniversitiesDetailed();
    for (final u in unis) {
      final uniId = u['id'] as String;
      final doc = await FirebaseFirestore.instance
          .collection('universities')
          .doc(uniId)
          .collection('allowed_ids')
          .doc(uniUniqueId)
          .get();
      if (doc.exists) return u;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchDepartments(String uniId) async {
    var snap = await FirebaseFirestore.instance
        .collection('universities')
        .doc(uniId)
        .collection('departments')
        .get();
    return snap.docs
        .map((d) =>
            <String, dynamic>{'id': d.id, 'name': d.data()['name'] ?? d.id})
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchSections(
      String uniId, String deptId) async {
    var snap = await FirebaseFirestore.instance
        .collection('universities')
        .doc(uniId)
        .collection('departments')
        .doc(deptId)
        .collection('sections')
        .get();
    return snap.docs
        .map((d) =>
            <String, dynamic>{'id': d.id, 'name': d.data()['name'] ?? d.id})
        .toList();
  }

  Future<bool> verifyUniUniqueId(String uniId, String uniUniqueId) async {
    if (uniId.isEmpty || uniUniqueId.isEmpty) return false;
    var doc = await FirebaseFirestore.instance
        .collection('universities')
        .doc(uniId)
        .collection('allowed_ids')
        .doc(uniUniqueId)
        .get();
    return doc.exists;
  }
}

// ==========================================
// AUTH VIEWS (UI)
// ==========================================

class LoginView extends StatefulWidget {
  const LoginView({super.key});
  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              SvgPicture.asset("assets/images/login.svg", height: 200),
              const BigText(text: "Login", color: AppColors.primaryBlack),
              const SizedBox(height: 20),
              
              TextFormField(
                  controller: _email,
                  decoration: MyDecoration().getDecoration(
                      icon: Icons.email,
                      label: const Text("Email"),
                      hintText: "Enter Email")),
              
              const SizedBox(height: 10),
              
              TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: MyDecoration().getDecoration(
                      icon: Icons.lock,
                      label: const Text("Password"),
                      hintText: "Enter Password")),
              
              const SizedBox(height: 20),
              
              BlueButton(
                text: "Login",
                onPressed: () async {
                  try {
                    // 1. Standard Firebase Auth Login
                    User? user = await AuthService()
                        .logIn(email: _email.text.trim(), password: _password.text);
                    
                    if (user != null) {
                      // Register FCM token for push notifications
                      try {
                        final token = await FirebaseMessaging.instance.getToken();
                        if (token != null) {
                          await NotificationService().registerFcmToken(userId: user.uid, token: token);
                        }
                      } catch (e) {
                        debugPrint('FCM token registration failed: $e');
                      }
                      // 2. CHECK DATABASE FOR ROLE & REDIRECT
                      final doc = await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .get();
                      
                      if (doc.exists) {
                        final role = (doc.data()?['role'] ?? '').toString();
                        
                        if (role == 'faculty') {
                          Get.offAllNamed('/faculty-dashboard'); 
                          return;
                        }
                        if (role == 'recruiter') {
                          Get.offAllNamed('/recruiter-dashboard');
                          return;
                        }
                        if (role == 'admin') {
                          Get.offAllNamed('/admin');
                          return;
                        }
                      }
                      
                      // 3. Default -> Student
                      if (!user.emailVerified) {
                          Get.to(() => const VerifyEmailView());
                      } else {
                          Get.offAllNamed('/dashboard');
                      }
                    }
                  } catch (e) {
                    // Error is handled in AuthService (shows snackbar)
                  }
                },
              ),
              
              const SizedBox(height: 20),
              
              InkWell(
                onTap: () => Get.to(() => const RegisterView()),
                child: const Text("Don't have an account? Student Sign Up",
                    style: TextStyle(color: AppColors.mainColor)),
              ),
              const SizedBox(height: 12),
              // FACULTY INVITE LINK
              InkWell(
                onTap: () => Get.to(() => const FacultyInviteScreen()),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.mainColor),
                    borderRadius: BorderRadius.circular(8)
                  ),
                  child: const Text("Have a Faculty Invite Code?",
                      style: TextStyle(color: AppColors.mainColor, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});
  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              SvgPicture.asset("assets/images/register.svg", height: 200),
              const BigText(text: "Register", color: AppColors.primaryBlack),
              const SizedBox(height: 20),
              TextFormField(
                  controller: _email,
                  decoration: MyDecoration().getDecoration(
                      icon: Icons.email,
                      label: const Text("University Email"),
                      hintText: "Enter your university email")),
              const SizedBox(height: 10),
              TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: MyDecoration().getDecoration(
                      icon: Icons.lock,
                      label: const Text("Password"),
                      hintText: "Choose a password")),
              const SizedBox(height: 20),
              BlueButton(
                text: "Next",
                onPressed: () {
                  final email = _email.text.trim();
                  final pass = _password.text;
                  if (email.isEmpty || pass.isEmpty) {
                    MySnackBar().mySnackBar(
                        header: "Missing",
                        content: "Enter email and password to continue",
                        bgColor: Colors.orange.shade100);
                    return;
                  }
                  Get.to(() => RegisterStep2View(email: email, password: pass));
                },
              )
            ]),
          ),
        ),
      ),
    );
  }
}

class RegisterStep2View extends StatefulWidget {
  final String email;
  final String password;
  const RegisterStep2View(
      {required this.email, required this.password, super.key});
  @override
  State<RegisterStep2View> createState() => _RegisterStep2State();
}

class _RegisterStep2State extends State<RegisterStep2View> {
  final _name = TextEditingController();
  final _uniUniqueId = TextEditingController();
  List<Map<String, dynamic>> _unis = [];
  List<Map<String, dynamic>> _depts = [];
  List<Map<String, dynamic>> _sections = [];
  String? _selectedUni;
  String? _selectedUniName;
  String? _selectedDept;
  String? _selectedSection;
  String _selectedShift = 'morning';
  String? _selectedSemester;

  @override
  void initState() {
    super.initState();
    _loadUnis();
    _detectUniFromEmail(widget.email);
  }

  void _loadUnis() async {
    try {
      _unis = await AuthService().fetchUniversities();
      setState(() {});
    } catch (e) {
      debugPrint('Failed to load universities: $e');
    }
  }

  void _detectUniFromEmail(String email) async {
    try {
      final local = email.split('@').first;
      final match = RegExp(r"\d{6}").firstMatch(local);
      if (match != null) {
        final uniIdCandidate = match.group(0)!;
        _uniUniqueId.text = uniIdCandidate;
        final uni = await AuthService().getUniversityByUniqueId(uniIdCandidate);
        if (uni != null) {
          _selectedUni = uni['id'] as String;
          _selectedUniName = uni['name'] as String;
          _loadDepts(_selectedUni!);
        }
      } else {
        // fallback: try domain detection
        final uni = await AuthService().getUniversityByEmail(email);
        if (uni != null) {
          _selectedUni = uni['id'] as String;
          _selectedUniName = uni['name'] as String;
          _loadDepts(_selectedUni!);
        }
      }
    } catch (e) {
      debugPrint('Uni detection failed: $e');
    }
    setState(() {});
  }

  void _loadDepts(String uniId) async {
    try {
      _depts = await AuthService().fetchDepartments(uniId);
      setState(() {});
    } catch (e) {
      debugPrint('Failed to load departments: $e');
    }
  }

  void _loadSections(String uniId, String deptId) async {
    try {
      _sections = await AuthService().fetchSections(uniId, deptId);
      setState(() {});
    } catch (e) {
      debugPrint('Failed to load sections: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Registration')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const BigText(
                text: 'Complete Profile', color: AppColors.primaryBlack),
            const SizedBox(height: 16),
            TextFormField(
                controller: _name,
                decoration: MyDecoration().getDecoration(
                    icon: Icons.person,
                    label: const Text('Full Name'),
                    hintText: 'Your name')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedUni,
              decoration: MyDecoration().getDecoration(
                  icon: Icons.school,
                  label: const Text('University'),
                  hintText: _unis.isEmpty
                      ? 'Loading universities...'
                      : 'Select University'),
              items: _unis
                  .map((u) => DropdownMenuItem(
                      value: u['id'] as String,
                      child: Text((u['name'] ?? u['id']) as String)))
                  .toList(),
              onChanged: _unis.isEmpty
                  ? null
                  : (v) {
                      _selectedUni = v;
                      _selectedUniName = _unis
                          .firstWhere((e) => e['id'] == v)['name'] as String?;
                      _selectedDept = null;
                      _selectedSection = null;
                      _depts = [];
                      _sections = [];
                      if (v != null) _loadDepts(v);
                      setState(() {});
                    },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _selectedDept,
              decoration: MyDecoration().getDecoration(
                  icon: Icons.account_tree,
                  label: const Text('Department'),
                  hintText: _depts.isEmpty
                      ? (_selectedUni == null
                          ? 'University not detected yet'
                          : 'Loading departments...')
                      : 'Select Department'),
              items: _depts
                  .map((d) => DropdownMenuItem(
                      value: d['id'] as String,
                      child: Text((d['name'] ?? d['id']) as String)))
                  .toList(),
              onChanged: _depts.isEmpty
                  ? null
                  : (v) {
                      _selectedDept = v;
                      _selectedSection = null;
                      _sections = [];
                      if (v != null && _selectedUni != null)
                        _loadSections(_selectedUni!, v);
                      setState(() {});
                    },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _selectedSection,
              decoration: MyDecoration().getDecoration(
                  icon: Icons.group,
                  label: const Text('Section'),
                  hintText: _sections.isEmpty
                      ? (_selectedDept == null
                          ? 'Select department first'
                          : 'Loading sections...')
                      : 'Select Section'),
              items: _sections
                  .map((s) => DropdownMenuItem(
                      value: s['id'] as String,
                      child: Text((s['name'] ?? s['id']) as String)))
                  .toList(),
              onChanged: _sections.isEmpty
                  ? null
                  : (v) {
                      _selectedSection = v;
                      setState(() {});
                    },
            ),
            const SizedBox(height: 10),
            Row(children: [
              const Text('Shift:'),
              const SizedBox(width: 12),
              DropdownButton<String>(
                  value: _selectedShift,
                  items: const [
                    DropdownMenuItem(value: 'morning', child: Text('Morning')),
                    DropdownMenuItem(value: 'evening', child: Text('Evening')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedShift = v);
                  })
            ]),
            const SizedBox(height: 10),
            Row(children: [
              const Text('Semester:'),
              const SizedBox(width: 12),
              DropdownButton<String>(
                  value: _selectedSemester,
                  hint: const Text('Select'),
                  items: List.generate(8, (i) => (i + 1).toString())
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedSemester = v);
                  })
            ]),
            const SizedBox(height: 10),
            TextFormField(
                controller: _uniUniqueId,
                decoration: MyDecoration().getDecoration(
                    icon: Icons.badge,
                    label: const Text('University ID'),
                    hintText: 'Detected from email')),
            const SizedBox(height: 20),
            BlueButton(
              text: 'Sign Up',
              onPressed: () async {
                try {
                  final missing = <String>[];
                  if (_name.text.trim().isEmpty) missing.add('Full name');
                  if (_selectedUni == null) missing.add('University');
                  if (_uniUniqueId.text.trim().isEmpty)
                    missing.add('University ID');
                  if (_depts.isNotEmpty &&
                      (_selectedDept == null || _selectedDept!.isEmpty))
                    missing.add('Department');
                  if (_sections.isNotEmpty &&
                      (_selectedSection == null || _selectedSection!.isEmpty))
                    missing.add('Section');
                  if (missing.isNotEmpty) {
                    await showDialog<void>(
                        context: context,
                        builder: (_) => AlertDialog(
                              title: const Text('Missing fields'),
                              content: Text(
                                  'Please complete: ${missing.join(', ')}'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: const Text('OK'))
                              ],
                            ));
                    return;
                  }

                  final uniUniqueId = _uniUniqueId.text.trim();
                  Map<String, dynamic>? uni;
                  if (_selectedUni != null) {
                    final all = await AuthService().fetchUniversitiesDetailed();
                    uni = all.firstWhere(
                        (u) => (u['id'] as String) == _selectedUni,
                        orElse: () => <String, dynamic>{});
                    if (uni.isEmpty) uni = null;
                  }
                  if (uni == null) {
                    uni = await AuthService()
                        .getUniversityByUniqueId(uniUniqueId);
                  }

                  if (uni == null) {
                    MySnackBar().mySnackBar(
                        header: 'University Not Found',
                        content:
                            'Could not find a university for this ID. Contact admin.',
                        bgColor: Colors.red.shade100);
                    return;
                  }

                  final uniId = uni['id'] as String;
                  final uniFromEmail =
                      await AuthService().getUniversityByEmail(widget.email);
                  if (uniFromEmail == null ||
                      (uniFromEmail['id'] as String) != uniId) {
                    MySnackBar().mySnackBar(
                        header: 'Email Domain Mismatch',
                        content:
                            'Email domain mismatch. Use your university email.',
                        bgColor: Colors.red.shade100);
                    return;
                  }

                  final requiresAllowed =
                      (uni['require_allowed_ids'] ?? false) as bool;
                  if (requiresAllowed) {
                    final ok = await AuthService()
                        .verifyUniUniqueId(uniId, uniUniqueId);
                    if (!ok) {
                      MySnackBar().mySnackBar(
                          header: 'Not Allowed',
                          content:
                              'This university does not recognize your student id.',
                          bgColor: Colors.red.shade100);
                      return;
                    }
                  }

                  await AuthService().createUser(
                      email: widget.email,
                      password: widget.password,
                      username: _name.text.trim(),
                      uniId: uniId,
                      departmentId: _selectedDept ?? '',
                      sectionId: _selectedSection ?? '',
                      shift: _selectedShift,
                      semester: _selectedSemester,
                      uniUniqueId: uniUniqueId);
                  await AuthService().sendEmailVerification();
                  Get.to(() => const VerifyEmailView());
                } catch (e) {
                  // handled in service
                }
              },
            )
          ]),
        ),
      ),
    );
  }
}

class VerifyEmailView extends StatelessWidget {
  const VerifyEmailView({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Verify Email")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const BigText(text: "Verify Email", color: Colors.black),
            const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                    "Please check your email and click the verification link.",
                    textAlign: TextAlign.center)),
            BlueButton(
                width: 200,
                onPressed: () => AuthService().sendEmailVerification(),
                text: "Resend Email"),
            const SizedBox(height: 12),
            BlueButton(
              width: 200,
              onPressed: () async {
                final verified = await AuthService().checkEmailVerified();
                if (verified) {
                  Get.offAllNamed('/dashboard');
                } else {
                  MySnackBar().mySnackBar(
                      header: "Not Verified",
                      content:
                          "Email not verified yet. Check your inbox or spam.",
                      bgColor: Colors.orange.shade100);
                }
              },
              text: "I have verified",
            ),
            TextButton(
                onPressed: () => Get.offAllNamed('/login'),
                child: const Text("Back to Login"))
          ],
        ),
      ),
    );
  }
}