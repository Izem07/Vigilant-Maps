import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'screens/map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Uses ios/Runner/GoogleService-Info.plist. If you run `flutterfire configure`,
  // switch to: Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
  await Firebase.initializeApp();
  runApp(const VigilantApp());
}

class VigilantApp extends StatelessWidget {
  const VigilantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vigilant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const MapScreen(),
    );
  }
}
