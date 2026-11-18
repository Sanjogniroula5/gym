import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final fmt = DateFormat('dd MMM yyyy');
const methods = ['Cash', 'eSewa', 'Khalti', 'Bank'];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
int daysLeft(DateTime exp) =>
    dateOnly(exp).difference(dateOnly(DateTime.now())).inDays;
String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime addMonths(DateTime d, int m) => DateTime(d.year, d.month + m, d.day);

const loader = Center(child: CircularProgressIndicator());

/// Shows a spinner, then an error message or the built widget.
Widget loadView<T>(Future<T> f, Widget Function(T) build) => FutureBuilder<T>(
      future: f,
      builder: (c, s) {
        if (s.hasError) return Center(child: Text('${s.error}'));
        if (!s.hasData) return loader;
        return build(s.data as T);
      },
    );
