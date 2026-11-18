import 'package:flutter/material.dart';
import 'api.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _id = TextEditingController();
  final _pw = TextEditingController();
  String? _err;
  bool _busy = false;

  Future<void> _login() async {
    setState(() { _busy = true; _err = null; });
    try {
      final r = await api('login', body: {'login_id': _id.text.trim(), 'password': _pw.text});
      await saveSession(Session(r['token'], r['role']));
    } on ApiError catch (e) {
      setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
            const Icon(Icons.fitness_center, size: 56),
            const SizedBox(height: 16),
            TextField(controller: _id, decoration: const InputDecoration(labelText: 'Login ID (phone number)')),
            TextField(
              controller: _pw,
              obscureText: true,
              onSubmitted: (_) => _login(),
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_err!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _busy ? null : _login, child: const Text('Login')),
          ]),
        ),
      ),
    );
  }
}
