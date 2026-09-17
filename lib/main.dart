import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'pantallas/login.dart'; // Llamamos a la pantalla de login desde su nueva carpeta

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const GourmetGuardApp());
}

class GourmetGuardApp extends StatelessWidget {
  const GourmetGuardApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gourmet Guard',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(primary: Colors.amber, secondary: Colors.amberAccent),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF000000), centerTitle: true, elevation: 4),
      ),
      home: const PantallaLogin(), // Iniciamos directamente en el Login
    );
  }
}
