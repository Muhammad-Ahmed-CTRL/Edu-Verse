import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class FacultyInviteScreen extends StatefulWidget {
  const FacultyInviteScreen({super.key});

  @override
  State<FacultyInviteScreen> createState() => _FacultyInviteScreenState();
}

class _FacultyInviteScreenState extends State<FacultyInviteScreen> {
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _linkedEmail; // We will fetch this from the code
  DocumentReference? _inviteRef; // reference to the invite doc we found

  // 1. Verify the Code
  Future<void> _verifyCode() async {
    setState(() => _isLoading = true);
    String code = _codeController.text.trim();

    final QuerySnapshot result = await FirebaseFirestore.instance
        .collection('invites')
        .where('code', isEqualTo: code)
        .where('isUsed', isEqualTo: false) // Must be unused
        .limit(1)
        .get();

    if (result.docs.isEmpty) {
      Get.snackbar("Error", "Invalid or Used Invite Code", backgroundColor: Colors.red.shade100);
      setState(() => _isLoading = false);
      return;
    }

    // Code is valid! Lock the email field to what was in the invite and keep the doc ref.
    final doc = result.docs.first;
    _linkedEmail = doc['email'];
    _inviteRef = doc.reference;
    setState(() => _isLoading = false);
  }

  // 2. Complete Registration
  Future<void> _registerFaculty() async {
    setState(() => _isLoading = true);
    
    try {
      if (_inviteRef == null) throw Exception('Invite not reserved. Please verify code first.');

      // Reserve the invite atomically to prevent races
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(_inviteRef!);
        if (!snap.exists) throw Exception('Invite not found');
        final used = snap.get('isUsed') as bool? ?? false;
        if (used) throw Exception('Invite already used');
        tx.update(_inviteRef!, {'isUsed': true, 'reservedAt': FieldValue.serverTimestamp()});
      });

      // A. Create Auth User
      UserCredential creds;
      try {
        creds = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _linkedEmail!, 
          password: _passwordController.text.trim(),
        );
      } catch (e) {
        // Revert reservation so invite remains usable
        try {
          await _inviteRef!.update({'isUsed': false, 'reservedAt': FieldValue.delete()});
        } catch (_) {}
        rethrow;
      }

      // B. Create User Profile with FACULTY Role
      await FirebaseFirestore.instance.collection('users').doc(creds.user!.uid).set({
        'name': "Professor",
        'email': _linkedEmail,
        'role': 'faculty', // Assigns faculty role
        'createdAt': FieldValue.serverTimestamp(),
      });

      // C. Finalize invite: mark used by this uid
      await _inviteRef!.update({
        'isUsed': true,
        'usedBy': creds.user!.uid,
        'usedAt': FieldValue.serverTimestamp(),
      });

      Get.offAllNamed('/faculty-dashboard'); // Navigate to Faculty Home

    } catch (e) {
      Get.snackbar("Error", e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Faculty Access")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.security, size: 60, color: Colors.blueGrey),
            const SizedBox(height: 20),
            
            if (_linkedEmail == null) ...[
              // STAGE 1: Enter Code
              const Text("Enter your Faculty Access Code", style: TextStyle(fontSize: 18)),
              const SizedBox(height: 20),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: "Invite Code (e.g. FAC-1234)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _verifyCode,
                child: _isLoading ? const CircularProgressIndicator() : const Text("Verify Code"),
              ),
            ] else ...[
              // STAGE 2: Set Password (Email is locked)
              Text("Welcome! Setup account for:", style: TextStyle(color: Colors.grey[600])),
              Text(_linkedEmail!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Create Password",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _registerFaculty,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text("Activate Faculty Account"),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
