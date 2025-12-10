// lib/screens/app_tour.dart
import 'package:flutter/material.dart';
import 'package:goal/screens/auth_screen.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTourScreen extends StatelessWidget {
  const AppTourScreen({super.key});

  Future<void> _completeTour(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tourCompleted', true);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IntroductionScreen(
      globalBackgroundColor: Theme.of(context).colorScheme.surface,
      pages: [
        _buildPage(
          title: "Welcome to GOAL",
          body: "Your all-in-one quiz and rewards app. Let's explore!",
          icon: Icons.emoji_events,
          color: Colors.amberAccent,
        ),
        _buildPage(
          title: "Earn Rewards",
          body: "Play quizzes, open gift boxes, and spin wheels to earn wallet money.",
          icon: Icons.card_giftcard,
          color: Colors.deepOrangeAccent,
        ),
        _buildPage(
          title: "Battle Mode",
          body: "Challenge friends using wallet amounts and win big.",
          icon: Icons.sports_kabaddi,
          color: Colors.redAccent,
        ),
        _buildPage(
          title: "PDF Store",
          body: "Buy study materials with wallet balance & read anytime.",
          icon: Icons.menu_book_rounded,
          color: Colors.indigoAccent,
        ),
        _buildPage(
          title: "Withdraw Money",
          body: "Withdraw your balance via UPI in the Account section.",
          icon: Icons.account_balance_wallet,
          color: Colors.green,
        ),
      ],
      onDone: () => _completeTour(context),
      onSkip: () => _completeTour(context),
      showSkipButton: true,
      skip: _buildButton(
        text: "Skip",
        color: Colors.grey.shade200,
        textColor: Colors.grey,
      ),
      next: _buildButton(
        child: const Icon(Icons.arrow_forward, color: Colors.white, size: 24),
        color: Colors.blueAccent,
      ),
      done: _buildButton(
        text: "Get Started",
        color: Colors.green,
        textColor: Colors.white,
      ),
      dotsDecorator: DotsDecorator(
        size: const Size(10.0, 10.0),
        color: Colors.grey.shade300,
        activeSize: const Size(22.0, 10.0),
        activeColor: Colors.blueAccent,
        activeShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25.0),
        ),
      ),
    );
  }

  PageViewModel _buildPage({
    required String title,
    required String body,
    required IconData icon,
    required Color color,
  }) {
    return PageViewModel(
      title: title,
      body: body,
      image: Icon(icon, size: 150, color: color),
      decoration: const PageDecoration(
        titleTextStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        bodyTextStyle: TextStyle(fontSize: 18),
        imagePadding: EdgeInsets.only(top: 40),
      ),
    );
  }

  Widget _buildButton({
    String? text,
    Widget? child,
    Color? color,
    Color textColor = Colors.white,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.only(bottom: 40),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: (color ?? Colors.grey).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child ?? Text(
        text!,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }
}