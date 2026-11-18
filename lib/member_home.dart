import 'package:flutter/material.dart';
import 'api.dart';
import 'common.dart';

class MemberHome extends StatefulWidget {
  const MemberHome({super.key});
  @override
  State<MemberHome> createState() => _MemberHomeState();
}

class _MemberHomeState extends State<MemberHome> {
  late Future<Map<String, dynamic>> _f = _load();
  Future<Map<String, dynamic>> _load() async => Map<String, dynamic>.from(await api('me'));
  void _reload() => setState(() => _f = _load());

  Future<void> _renew() async {
    try {
      await api('renew_request', body: {});
      _reload();
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Membership'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _reload),
        IconButton(icon: const Icon(Icons.logout), onPressed: logout),
      ]),
      body: loadView<Map<String, dynamic>>(_f, (d) {
        final m = d['member'] as Map;
        final exp = DateTime.parse(m['expiry_date']);
        final left = daysLeft(exp);
        final paid = m['status'] == 'paid';
        final pending = d['renew_pending'] == true;
        final pays = (d['payments'] as List);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(children: [
                    Text('Hi ${m['name']}', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Text(left < 0 ? 'Expired' : '$left',
                        style: TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            color: left <= 2 ? Colors.red : Colors.green[700])),
                    Text(left < 0 ? 'Please renew your membership' : 'days left'),
                    const Divider(height: 32),
                    _row('Plan', '${m['duration_months']} month(s)'),
                    _row('Expires on', fmt.format(exp)),
                    _row('Status', paid ? 'Paid' : 'Unpaid'),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.autorenew),
                label: Text(pending ? 'Request sent to owner' : 'I want to renew'),
                onPressed: pending ? null : _renew,
              ),
              const SizedBox(height: 24),
              Text('Payment history', style: Theme.of(context).textTheme.titleMedium),
              if (pays.isEmpty) const ListTile(title: Text('No payments yet')),
              ...pays.map((x) => ListTile(
                    leading: const Icon(Icons.receipt_long),
                    title: Text('Rs ${x['amount']}'),
                    subtitle: Text('${fmt.format(DateTime.parse(x['paid_at']))}  •  ${x['method']}'),
                  )),
            ]),
          ),
        );
      }),
    );
  }

  Widget _row(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(a), Text(b, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );
}
