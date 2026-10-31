import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Candidate {
  Candidate({this.id = '', required this.name, this.votes = 0});

  final String id;
  final String name;
  final int votes;

  Map<String, dynamic> toMap() => {'name': name, 'votes': votes};

  factory Candidate.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Candidate(
      id: doc.id,
      name: data['name'] as String,
      votes: (data['votes'] as num).toInt(),
    );
  }
}

// The signed-in user's own document: users/{uid}
DocumentReference<Map<String, dynamic>> _me() {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  return FirebaseFirestore.instance.collection('users').doc(uid);
}

CollectionReference<Map<String, dynamic>> myCandidates() =>
    _me().collection('candidates');

CollectionReference<Map<String, dynamic>> myVoters() =>
    _me().collection('voters');

// Is this name already used by another candidate?
Future<bool> nameTaken(String name, {String? exceptId}) async {
  final snap = await myCandidates().get();
  return snap.docs.any((d) =>
  d.id != exceptId &&
      (d.data()['name'] as String).toLowerCase() == name.toLowerCase());
}

// Sample data, written once when a new account is created
Future<void> addSampleCandidates() async {
  final batch = FirebaseFirestore.instance.batch();
  for (final name in ['Aline', 'Keza', 'Mutoni']) {
    batch.set(myCandidates().doc(), Candidate(name: name).toMap());
  }
  await batch.commit();
}