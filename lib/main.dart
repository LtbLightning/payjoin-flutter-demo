import 'package:flutter/material.dart';
import 'package:payjoin_flutter_demo/screens/home.dart';
import 'package:payjoin_flutter_demo/styles/theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PayJoin Flutter Demo',
      theme: theme(),
      home: const Home(),
    );
  }
}
