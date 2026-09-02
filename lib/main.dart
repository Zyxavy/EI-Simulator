import 'package:ei_simulator/database/db_helper.dart';
import 'package:ei_simulator/providers/person_provider.dart';
import 'package:ei_simulator/screens/graph_screen.dart';
import 'package:ei_simulator/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DbHelper.instance.seedDatabase();
  runApp(
    ChangeNotifierProvider(
      create: (_) => PersonProvider()..loadAll(),
      child: const MainApp(),
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: '/',
      routes: {
        '/': (context) => const GraphScreen(),
      },
    );
  }
}
