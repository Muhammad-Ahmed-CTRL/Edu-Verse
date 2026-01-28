import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminNotifications extends StatelessWidget {
  final String? adminUniId;
  const AdminNotifications({Key? key, this.adminUniId}) : super(key: key);

  Stream<QuerySnapshot> _stream() {
    final db = FirebaseFirestore.instance;
    if (adminUniId == null) {
      return db
          .collection('job_requests')
          .orderBy('createdAt', descending: true)
          .snapshots();
    }
    return db
        .collection('job_requests')
        .where('pendingFor', arrayContains: adminUniId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<QuerySnapshot>(
        stream: _stream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snap.hasData || snap.data!.docs.isEmpty) return const Center(child: Text('No notifications'));
          return ListView(
            children: snap.data!.docs.map((d) {
              final data = d.data() as Map<String, dynamic>;
              final job = data['job'] as Map<String, dynamic>? ?? {};
              final status = data['status'] ?? 'pending';
              return ListTile(
                title: Text(job['title'] ?? 'Job Request'),
                subtitle: Text('From: ${data['recruiterEmail'] ?? ''} • Status: $status'),
                trailing: status == 'pending' ? const Icon(Icons.pending) : const Icon(Icons.check_circle, color: Colors.green),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
