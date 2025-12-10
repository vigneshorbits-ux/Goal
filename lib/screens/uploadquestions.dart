import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddQuestionsScreen extends StatelessWidget {
  const AddQuestionsScreen({super.key});

  Future<void> addQuizQuestionsToFirestore() async {
    final questions = 
[
 {
  "question": "What is the full form of 'IBPS'?",
  "options": ["Indian Banking Personnel Service", "Institute of Banking Personnel Selection", "International Bank Promotion Society", "Indian Bureau of Public Sector"],
  "answer": "Institute of Banking Personnel Selection",
  "category": "Banking Awareness",
  "difficulty": "Easy"
},

];

    for (var question in questions) {
      await FirebaseFirestore.instance.collection('quizQuestions').add(question);
    }

    print("Questions added successfully!");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Add Questions"),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            try {
              await addQuizQuestionsToFirestore();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Questions added successfully!")),
              );
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Error: $e")),
              );
            }
          },
          child: const Text("Upload Questions to Firestore"),
        ),
      ),
    );
  }
}
