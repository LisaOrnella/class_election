import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'auth_gate.dart';
import 'candidate.dart';
import 'firebase_options.dart';
import 'weather.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ElectionApp());
}

String cleanName(String name) {
  final words = name.trim().split(' ').where((w) => w.isNotEmpty);
  final fixed = words.map((w) {
    return w.substring(0, 1).toUpperCase() + w.substring(1).toLowerCase();
  });
  return fixed.join(' ');
}

String voteWord(int count) {
  return count == 1 ? 'vote' : 'votes';
}

int totalVotes(List<Candidate> list) {
  int total = 0;
  for (final candidate in list) {
    total += candidate.votes;
  }
  return total;
}

List<Candidate> rankedCandidates(List<Candidate> list) {
  final ranked = [...list];
  ranked.sort((a, b) => b.votes.compareTo(a.votes));
  return ranked;
}

String bannerText(List<Candidate> ranked) {
  final top = ranked.first.votes;
  final leaders = ranked.where((c) => c.votes == top).toList();
  if (leaders.length == 1) {
    return 'Winner: ${leaders.first.name}';
  }
  final names = leaders.map((c) => c.name).join(' and ');
  return 'Tie between $names ($top ${voteWord(top)} each)';
}

Widget errorView(Object? error) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text('Could not load your data.\n$error', textAlign: TextAlign.center),
    ),
  );
}

class ElectionApp extends StatelessWidget {
  const ElectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Class Election',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const AuthGate(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final nameController = TextEditingController();

  void showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> vote(Candidate candidate) async {
    final voter = cleanName(nameController.text);
    if (voter.isEmpty) {
      showMessage('Type your name first');
      return;
    }
    // The voter's name is the document id, so one name can only exist once
    final voterDoc = myVoters().doc(voter.toLowerCase().replaceAll('/', '_'));
    try {
      final existing = await voterDoc.get();
      if (existing.exists) {
        showMessage('$voter has already voted');
        return;
      }
      final batch = FirebaseFirestore.instance.batch();
      batch.set(voterDoc, {'name': voter});
      batch.update(myCandidates().doc(candidate.id),
          {'votes': FieldValue.increment(1)});
      await batch.commit();
      nameController.clear();
      showMessage('Thank you $voter, your vote for ${candidate.name} is counted');
    } catch (e) {
      showMessage('Could not save your vote: $e');
    }
  }

  void openCandidates() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CandidatesScreen()),
    );
  }

  void openResults() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ResultsScreen()),
    );
  }

  Future<void> resetAll() async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final cands = await myCandidates().get();
      for (final doc in cands.docs) {
        batch.update(doc.reference, {'votes': 0});
      }
      final voters = await myVoters().get();
      for (final doc in voters.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      showMessage('All votes cleared');
    } catch (e) {
      showMessage('Could not reset: $e');
    }
  }

  void confirmReset() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reset all votes?'),
          content: const Text('Every vote and every voter will be cleared.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                resetAll();
              },
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Class Election'),
        actions: [
          IconButton(icon: const Icon(Icons.group), onPressed: openCandidates),
          IconButton(icon: const Icon(Icons.bar_chart), onPressed: openResults),
          IconButton(icon: const Icon(Icons.restart_alt), onPressed: confirmReset),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const WeatherBox(),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Your name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: myCandidates().orderBy('name').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return errorView(snapshot.error);
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final list =
                  snapshot.data!.docs.map(Candidate.fromDoc).toList();
                  if (list.isEmpty) {
                    return const Center(
                      child: Text('No candidates yet. Add one with the group icon.'),
                    );
                  }
                  return Column(
                    children: [
                      Text('Votes so far: ${totalVotes(list)}'),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final candidate = list[index];
                            return Card(
                              child: ListTile(
                                title: Text(candidate.name),
                                subtitle: Text(
                                  '${candidate.votes} ${voteWord(candidate.votes)}',
                                ),
                                trailing: FilledButton(
                                  onPressed: () => vote(candidate),
                                  child: const Text('Vote'),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CandidatesScreen extends StatefulWidget {
  const CandidatesScreen({super.key});

  @override
  State<CandidatesScreen> createState() => _CandidatesScreenState();
}

class _CandidatesScreenState extends State<CandidatesScreen> {
  final nameController = TextEditingController();

  void showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> addCandidate() async {
    final name = cleanName(nameController.text);
    if (name.isEmpty) {
      showMessage('Type a name first');
      return;
    }
    try {
      if (await nameTaken(name)) {
        showMessage('$name is already a candidate');
        return;
      }
      await myCandidates().add(Candidate(name: name).toMap());
      nameController.clear();
      showMessage('$name added');
    } catch (e) {
      showMessage('Could not add: $e');
    }
  }

  Future<void> editCandidate(Candidate candidate) async {
    final controller = TextEditingController(text: candidate.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit candidate'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, cleanName(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty) return;
    try {
      if (await nameTaken(newName, exceptId: candidate.id)) {
        showMessage('$newName is already a candidate');
        return;
      }
      await myCandidates().doc(candidate.id).update({'name': newName});
      showMessage('Updated to $newName');
    } catch (e) {
      showMessage('Could not edit: $e');
    }
  }

  Future<void> removeCandidate(Candidate candidate) async {
    if (candidate.votes > 0) {
      showMessage('${candidate.name} already has votes and cannot be removed');
      return;
    }
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this candidate?'),
        content: Text(candidate.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await myCandidates().doc(candidate.id).delete();
      showMessage('${candidate.name} removed');
    } catch (e) {
      showMessage('Could not delete: $e');
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Candidates')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'New candidate',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(onPressed: addCandidate, child: const Text('Add')),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: myCandidates().orderBy('name').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return errorView(snapshot.error);
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final list =
                  snapshot.data!.docs.map(Candidate.fromDoc).toList();
                  if (list.isEmpty) {
                    return const Center(child: Text('No candidates yet'));
                  }
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final candidate = list[index];
                      return Card(
                        child: ListTile(
                          title: Text(candidate.name),
                          subtitle: Text(
                            '${candidate.votes} ${voteWord(candidate.votes)}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => editCandidate(candidate),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () => removeCandidate(candidate),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: myCandidates().snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return errorView(snapshot.error);
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snapshot.data!.docs.map(Candidate.fromDoc).toList();
          final total = totalVotes(list);
          if (list.isEmpty || total == 0) {
            return const Center(child: Text('No votes yet'));
          }
          final ranked = rankedCandidates(list);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.teal,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    bannerText(ranked),
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: ranked.length,
                    itemBuilder: (context, index) {
                      final candidate = ranked[index];
                      final share = candidate.votes / total;
                      return ListTile(
                        title: Text('${index + 1}. ${candidate.name}'),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: LinearProgressIndicator(
                            value: share,
                            minHeight: 12,
                          ),
                        ),
                        trailing: Text(
                          '${candidate.votes} ${voteWord(candidate.votes)}\n${(share * 100).toStringAsFixed(1)}%',
                          textAlign: TextAlign.right,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}