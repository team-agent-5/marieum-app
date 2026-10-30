import 'package:flutter/material.dart';

void main() => runApp(const MarieumApp());

class MarieumApp extends StatelessWidget {
  const MarieumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: '말이음',
      home: Scaffold(
        body: Center(child: Text('말이음')),
      ),
    );
  }
}
