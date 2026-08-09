import 'package:flutter/material.dart';

import 'state/app_controller.dart';
import 'ui/home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  controller.bootstrapApp();
  runApp(VibeStudioApp(controller: controller));
}

class VibeStudioApp extends StatelessWidget {
  final AppController controller;

  const VibeStudioApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vibe Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF14151A),
        useMaterial3: true,
      ),
      home: HomePage(controller: controller),
    );
  }
}
