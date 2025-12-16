# llmobservability

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.





import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:llmobservability/Screens/DashboardScreen.dart';
import 'package:llmobservability/Screens/ChatScreen.dart'; // <-- Add this import

void main() {
runApp(const MyApp());
}

class MyApp extends StatelessWidget {
const MyApp({super.key});

@override
Widget build(BuildContext context) {
return MaterialApp(
title: 'LLM Observability Dashboard',
theme: ThemeData(
primarySwatch: Colors.deepPurple,
useMaterial3: true,
),
home: const MainNavigationScreen(), // <-- New wrapper screen with navbar
debugShowCheckedModeBanner: false,
);
}
}

// New screen that holds the BottomNavigationBar
class MainNavigationScreen extends StatefulWidget {
const MainNavigationScreen({super.key});

@override
State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
int _selectedIndex = 0;

// List of screens for each tab
static const List<Widget> _screens = <Widget>[
DashboardScreen(),
ChatScreen(), // Make sure this class exists
];

void _onItemTapped(int index) {
setState(() {
_selectedIndex = index;
});
}

@override
Widget build(BuildContext context) {
return Scaffold(
body: _screens[_selectedIndex], // Show the selected screen
bottomNavigationBar: BottomNavigationBar(
items: const <BottomNavigationBarItem>[
BottomNavigationBarItem(
icon: Icon(Icons.dashboard),
label: 'Dashboard',
),
BottomNavigationBarItem(
icon: Icon(Icons.chat),
label: 'Chat',
),
],
currentIndex: _selectedIndex,
selectedItemColor: Colors.deepPurple,
unselectedItemColor: Colors.grey,
onTap: _onItemTapped,
),
);
}
}