import 'package:flutter/material.dart';
import 'admin_home.dart';
import 'api.dart';
import 'login_page.dart';
import 'member_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadSession();
  runApp(MaterialApp(
    title: 'Gym',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
    home: ValueListenableBuilder<Session?>(
      valueListenable: session,
      builder: (c, s, _) {
        if (s == null) return const LoginPage();
        return s.role == 'admin' ? const AdminHome() : const MemberHome();
      },
    ),
  ));
}
