import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:goal/leaderboard_service.dart';
import 'package:goal/screens/google_sheet_service.dart';

class QuizScreen extends StatefulWidget {
  final int numberOfQuestions;
  final String username;
  final bool isBattleMode;
  final String? battleId;
  final String? opponent;
  final int? prize;
  final String language; // 👈 NEW

  const QuizScreen({
    super.key,
    required this.numberOfQuestions,
    required this.username,
    this.isBattleMode = false,
    this.battleId,
    this.opponent,
    this.prize,
    this.language = "English", // 👈 default language
  });

  @override
  _QuizScreenState createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  static const _questionTimeLimit = 15;

  List<Map<String, dynamic>> _quizQuestions = [];
  int _currentQuestionIndex = 0;
  int _score = 0;
  int _timeLeft = _questionTimeLimit;
  String? _selectedAnswer;
  bool _isLoading = true;
  bool _fetchError = false;
  bool _isAnswerEvaluated = false;
  Timer? _timer;

  final LeaderboardService _leaderboardService =
      LeaderboardService(firestore: FirebaseFirestore.instance);

  @override
  void initState() {
    super.initState();
    _initializeQuiz();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initializeQuiz() async {
    try {
      if (widget.isBattleMode) {
        await _fetchBattleQuestions();
      } else {
        await _fetchQuestions();
      }

      setState(() {
        _isLoading = false;
        _timeLeft = _questionTimeLimit;
      });

      _startTimer();
    } catch (e) {
      _handleError("Initialization error: $e");
    }
  }

  Future<void> _fetchBattleQuestions() async {
    final battleRef =
        FirebaseFirestore.instance.collection('battles').doc(widget.battleId);
    final battleDoc = await battleRef.get();

    if (!battleDoc.exists) throw Exception("Battle not found");

    final questions = List<Map<String, dynamic>>.from(battleDoc['questions']);
    _quizQuestions = questions;
  }

  Future<void> _fetchQuestions() async {
    try {
      /// 👇 Select Google Sheet based on selected language
      String csvUrl;

      if (widget.language == "Tamil") {
        csvUrl =
            "https://docs.google.com/spreadsheets/d/e/2PACX-1vReb2TeAg3FtKWnGdF8Z3WEecdwBsXpZcCeKqLba39euoBtHt6ehceVAl1yHvvHdZ1484nfbj2fyuj-/pub?output=csv";
      } else if (widget.language == "Hindi") {
        csvUrl =
            "https://docs.google.com/spreadsheets/d/e/2PACX-1vRHGslBiEb-oIESkuJ2EnaCulb-3jOglI35VyogCZD9mCn89IzJ8z5qMbYlG8qBpwjBO8mvgnjxobxm/pub?output=csv";
      } else {
        csvUrl =
            "https://docs.google.com/spreadsheets/d/e/2PACX-1vQHtA8_3vH6TjRCb3aJA8ayircjC0qPj3f8As_kiAKMvwbFLzs2WeQdRinjnSHd2uB35kRH_49Ytkj2/pub?output=csv";
      }

      final sheetService = GoogleSheetService(csvUrl: csvUrl);
      final sheetQuestions = await sheetService.fetchQuestionsFromSheet();

      sheetQuestions.shuffle();
      _quizQuestions = sheetQuestions.take(widget.numberOfQuestions).toList();

      print("✅ Loaded ${widget.language} questions from Google Sheet");
    } catch (e) {
      print("⚠️ Google Sheet failed. Falling back to Firestore. Error: $e");

      // 👇 fallback Firestore collection based on language
      final snapshot = await FirebaseFirestore.instance
          .collection("quizQuestions_${widget.language.toLowerCase()}")
          .get();

      final firestoreQuestions =
          snapshot.docs.map((doc) => doc.data()).toList();

      firestoreQuestions.shuffle();
      _quizQuestions =
          firestoreQuestions.take(widget.numberOfQuestions).toList();

      print("✅ Loaded ${widget.language} questions from Firestore");
    }

    setState(() {});
  }

  // ⬇️ The rest of your existing code (timer, answer evaluation, result dialog, build UI) stays the same
  // no need to repeat it here because only fetching logic changed




  void _startTimer() {
    _timer?.cancel();
    _timeLeft = _questionTimeLimit;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft > 0) {
        setState(() => _timeLeft--);
      } else {
        _handleAnswerSubmitted(null);
      }
    });
  }

  void _handleAnswerSubmitted(String? answer) {
    _timer?.cancel();
    _evaluateAnswer(answer);
    setState(() {
      _selectedAnswer = answer;
      _isAnswerEvaluated = true;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _moveToNextQuestion();
    });
  }

  void _evaluateAnswer(String? answer) {
    final correctAnswer =
        _currentQuestion['answer']?.toString().toLowerCase().trim();
    final userAnswer = answer?.toLowerCase().trim();

    if (userAnswer == correctAnswer) {
      _score++;
    }
  }

  void _moveToNextQuestion() {
    if (_currentQuestionIndex < _quizQuestions.length - 1) {
      setState(() {
        _currentQuestionIndex++;
        _selectedAnswer = null;
        _timeLeft = _questionTimeLimit;
        _isAnswerEvaluated = false;
      });
      _startTimer();
    } else {
      _submitQuizResults();
    }
  }

  Future<void> _submitQuizResults() async {
    try {
      if (widget.isBattleMode) {
        await _submitBattleResult();
      } else {
        await _submitRegularQuiz();
      }

      _showResultDialog();
    } catch (e) {
      _handleError("Error submitting quiz: $e");
    }
  }

  Future<void> _submitBattleResult() async {
    final battleRef = FirebaseFirestore.instance
        .collection('battles')
        .doc(widget.battleId);

    await battleRef.update({
      'results.${widget.username}': {
        'score': _score,
        'completedAt': Timestamp.now(),
      },
      'completedUsers': FieldValue.arrayUnion([widget.username]),
    });
  }

  Future<void> _submitRegularQuiz() async {
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.username);

    await userRef.collection('dailyScores').add({
      'date': Timestamp.now(),
      'score': _score,
    });

    final dailyScores = await userRef
        .collection('dailyScores')
        .orderBy('date', descending: true)
        .limit(7)
        .get();

    final total = dailyScores.docs
        .map((d) => d['score'] as int)
        .fold(0, (a, b) => a + b);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _leaderboardService.updateLeaderboard(
        user.uid,
        widget.username,
        total,
      );
    }
  }

  Map<String, dynamic> get _currentQuestion =>
      _quizQuestions[_currentQuestionIndex];

  void _handleError(String error) {
    debugPrint(error);
    setState(() {
      _fetchError = true;
      _isLoading = false;
    });
  }

 List<Widget> _buildAnswerOptions() {
  // Support both Firestore and Google Sheet formats
  List<String> options = [];

  if (_currentQuestion.containsKey('options')) {
    // Firestore format (assumes list under 'options' key)
    options = List<String>.from(_currentQuestion['options'] ?? []);
  } else {
    // Google Sheets format (options are in separate columns)
    for (int i = 1; i <= 4; i++) {
      final opt = _currentQuestion['option$i'];
      if (opt != null && opt.toString().trim().isNotEmpty) {
        options.add(opt.toString());
      }
    }
  }

  final correctAnswer = _currentQuestion['answer']?.toString().toLowerCase();

  return options.map((option) {
    final isSelected = _selectedAnswer == option;
    final isCorrect = option.toLowerCase() == correctAnswer;
    final isAnswered = _selectedAnswer != null;

    Color backgroundColor;
    if (_isAnswerEvaluated) {
      if (isCorrect) {
        backgroundColor = Colors.green.shade400;
      } else if (isSelected && !isCorrect) {
        backgroundColor = Colors.red.shade400;
      } else {
        backgroundColor = Colors.grey.shade400;
      }
    } else {
      backgroundColor = Colors.blue.shade400;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: backgroundColor,
        boxShadow: [
          if (!_isAnswerEvaluated && isSelected)
            BoxShadow(
              color: Colors.blue.withOpacity(0.5),
              blurRadius: 6,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _isAnswerEvaluated
              ? null
              : () {
                  _handleAnswerSubmitted(option);
                },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    option,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (_isAnswerEvaluated)
                  Icon(
                    isCorrect
                        ? Icons.check_circle
                        : (isSelected ? Icons.cancel : null),
                    color: Colors.white,
                    size: 24,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }).toList();
}
  

  void _showResultDialog() {
    final percentage = (_score / _quizQuestions.length) * 100;
    Color resultColor;
    String resultMessage;

    if (percentage >= 80) {
      resultColor = Colors.green;
      resultMessage = 'Excellent!';
    } else if (percentage >= 50) {
      resultColor = Colors.orange;
      resultMessage = 'Good job!';
    } else {
      resultColor = Colors.red;
      resultMessage = 'Keep practicing!';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(
          widget.isBattleMode ? 'Battle Complete' : 'Quiz Complete',
          style: TextStyle(color: resultColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              resultMessage,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: resultColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Score: $_score / ${_quizQuestions.length}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _score / _quizQuestions.length,
              backgroundColor: Colors.grey[300],
              color: resultColor,
              minHeight: 10,
            ),
            if (widget.isBattleMode && widget.opponent != null) ...[
              const SizedBox(height: 20),
              Text(
                'Opponent: ${widget.opponent}',
                style: const TextStyle(fontSize: 16),
              ),
              if (widget.prize != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Prize: ${widget.prize} points',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
              ],
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            child: const Text(
              'OK',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(
                'Loading questions...',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    if (_fetchError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 50, color: Colors.red),
              const SizedBox(height: 20),
              const Text(
                'Failed to load questions',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _initializeQuiz,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isBattleMode
            ? 'Battle Quiz (${widget.username})'
            : 'Quiz (${widget.username})'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'Score: $_score',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Progress indicator
            Column(
              children: [
                LinearProgressIndicator(
                  value: (_currentQuestionIndex + 1) / _quizQuestions.length,
                  minHeight: 8,
                  backgroundColor: Colors.grey[300],
                  color: Colors.blue,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Question ${_currentQuestionIndex + 1} of ${_quizQuestions.length}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      '${((_currentQuestionIndex + 1) / _quizQuestions.length * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Timer
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: _timeLeft <= 5 ? Colors.red.shade100 : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timer,
                    color: _timeLeft <= 5 ? Colors.red : Colors.blue,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$_timeLeft seconds',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _timeLeft <= 5 ? Colors.red : Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Question
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _currentQuestion['question'] ?? '',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Answer options
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: _buildAnswerOptions(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}