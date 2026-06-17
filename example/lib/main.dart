import 'package:flutter/material.dart';

import 'app.dart';
import 'custom_nav_ui.dart';

void main() => runApp(const ExampleApp());

/// Root of the example app — a small menu that opens each demo.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mapbox Navigation Plus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1A73E8),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mapbox Navigation Plus')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DemoCard(
            icon: Icons.navigation_rounded,
            title: 'Custom Navigation UI',
            subtitle: 'A fully custom Flutter turn-by-turn UI built on the '
                'embedded map: maneuver card, ETA, speed, markers, alternative '
                'routes and "add a stop".',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CustomNavUiPage(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _DemoCard(
            icon: Icons.tune_rounded,
            title: 'Feature Playground',
            subtitle: 'Full-screen & embedded navigation, free drive, map '
                'styles and offline regions.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PlaygroundPage(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoCard extends StatelessWidget {
  const _DemoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.chevron_right),
        isThreeLine: true,
        onTap: onTap,
      ),
    );
  }
}
