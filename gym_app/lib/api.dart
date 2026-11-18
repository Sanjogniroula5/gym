import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Set at run time:  flutter run --dart-define=API=http://10.0.2.2/gym_api/index.php
const apiBase = String.fromEnvironment('API', defaultValue: 'http://localhost/gym_api/index.php');

class Session {
  Session(this.token, this.role);
  final String token, role;
}

final session = ValueNotifier<Session?>(null);

class ApiError implements Exception {
  ApiError(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<void> loadSession() async {
  final p = await SharedPreferences.getInstance();
  final t = p.getString('token'), r = p.getString('role');
  if (t != null && r != null) session.value = Session(t, r);
}

Future<void> saveSession(Session? s) async {
  final p = await SharedPreferences.getInstance();
  if (s == null) {
    await p.remove('token');
    await p.remove('role');
  } else {
    await p.setString('token', s.token);
    await p.setString('role', s.role);
  }
  session.value = s;
}

Future<void> logout() => saveSession(null);

/// GET when [body] is null, POST otherwise. Returns decoded JSON.
Future<dynamic> api(String route, {Map<String, dynamic>? body}) async {
  final uri = Uri.parse(apiBase).replace(queryParameters: {'r': route});
  final headers = {
    'Content-Type': 'application/json',
    if (session.value != null) 'X-Auth-Token': session.value!.token,
  };
  http.Response res;
  try {
    res = body == null
        ? await http.get(uri, headers: headers)
        : await http.post(uri, headers: headers, body: jsonEncode(body));
  } catch (_) {
    throw ApiError('Cannot reach the server');
  }
  dynamic data;
  try {
    data = jsonDecode(res.body);
  } catch (_) {
    throw ApiError('Server error');
  }
  if (res.statusCode == 401 && session.value != null && route != 'login') await logout();
  if (res.statusCode >= 400) throw ApiError(data['error'] ?? 'Something went wrong');
  return data;
}
