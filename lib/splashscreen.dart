import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:taskhaura/register.dart';
import 'package:taskhaura/screens/mainscreen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _routeNext();
  }

  Future<void> _routeNext() async {
    // wait until Firebase auth state is ready
    final user = FirebaseAuth.instance.currentUser;

    // tiny artificial pause so the splash is visible
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    final route = user == null
        ? MaterialPageRoute(builder: (_) => const RegisterPage())
        : MaterialPageRoute(builder: (_) => const MainScreen());

    Navigator.of(context).pushReplacement(route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/taskhauralogo.png', width: 120, height: 120),
            const SizedBox(height: 10),
            const Text(
              'Task Haura',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(
              color: Colors.deepPurple,
              strokeWidth: 3,
            ),
          ],
        ),
      ),
    );
  }
}