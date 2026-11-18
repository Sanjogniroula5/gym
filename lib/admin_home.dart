import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'common.dart';

typedef Json = Map<String, dynamic>;

/// Bump this to make the tabs reload from the server.
final refresh = ValueNotifier<int>(0);

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gym Admin'),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: () => refresh.value++),
            IconButton(icon: const Icon(Icons.logout), onPressed: logout),
          ],
          bottom: TabBar(onTap: (_) => refresh.value++, tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Dashboard'),
            Tab(icon: Icon(Icons.people), text: 'Members'),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.person_add),
          label: const Text('New Member'),
          onPressed: () async {
            final r = await Navigator.push<Json>(
                context, MaterialPageRoute(builder: (_) => const AddMemberPage()));
            if (r != null) {
              refresh.value++;
              if (context.mounted) showCreds(context, r['login_id'], r['password']);
            }
          },
        ),
        body: const TabBarView(children: [DashboardTab(), MembersTab()]),
      ),
    );
  }
}

// ------------------------------------------------------------ shared dialogs
void showCreds(BuildContext context, String id, String pw, {String title = 'Member login'}) {
  final text = 'Login ID: $id\nPassword: $pw';
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SelectableText(text),
      actions: [
        TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: text)), child: const Text('Copy')),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
      ],
    ),
  );
}

Future<Json?> payDialog(BuildContext context, String title, {bool withMonths = false}) {
  final amount = TextEditingController();
  var method = methods.first;
  var months = 1;
  return showDialog<Json>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (withMonths)
            DropdownButtonFormField<int>(
              value: months,
              decoration: const InputDecoration(labelText: 'Months'),
              items: [1, 3, 6, 12].map((m) => DropdownMenuItem(value: m, child: Text('$m'))).toList(),
              onChanged: (v) => set(() => months = v!),
            ),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount (Rs)'),
          ),
          DropdownButtonFormField<String>(
            value: method,
            decoration: const InputDecoration(labelText: 'Payment method'),
            items: methods.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
            onChanged: (v) => set(() => method = v!),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final a = int.tryParse(amount.text.trim());
              if (a == null || a <= 0) return;
              Navigator.pop(ctx, {'amount': a, 'method': method, 'months': months});
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------- DASHBOARD
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});
  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  late Future<Json> _f = _load();
  Future<Json> _load() async => Json.from(await api('dashboard'));
  void _reload() { if (mounted) setState(() => _f = _load()); }

  @override
  void initState() { super.initState(); refresh.addListener(_reload); }
  @override
  void dispose() { refresh.removeListener(_reload); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return loadView<Json>(_f, (d) {
      final reqs = d['renew_requests'] as List;
      return ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          _Stat('Total members', '${d['total']}', Icons.groups),
          _Stat('Active', '${d['active']}', Icons.check_circle),
          _Stat('Expired', '${d['expired']}', Icons.event_busy),
          _Stat('Unpaid', '${d['unpaid']}', Icons.money_off),
          _Stat("Today's check-ins", '${d['checkins']}', Icons.login),
          _Stat('Revenue this month', 'Rs ${d['revenue']}', Icons.payments),
        ]),
        const SizedBox(height: 24),
        Text('Renew requests', style: Theme.of(context).textTheme.titleMedium),
        if (reqs.isEmpty) const ListTile(title: Text('No pending requests')),
        ...reqs.map((r) => ListTile(
              leading: const Icon(Icons.autorenew),
              title: Text('${r['name']} wants to renew'),
              subtitle: Text('${r['phone']}'),
              trailing: TextButton(
                onPressed: () async {
                  await api('renew_seen', body: {'id': r['id']});
                  _reload();
                },
                child: const Text('Done'),
              ),
            )),
      ]);
    });
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon);
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 170,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon),
              const SizedBox(height: 8),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              Text(label),
            ]),
          ),
        ),
      );
}

// ------------------------------------------------------------------ MEMBERS
class MembersTab extends StatefulWidget {
  const MembersTab({super.key});
  @override
  State<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<MembersTab> {
  String _q = '', _f = 'All';
  static const _filters = ['All', 'Unpaid', 'Expiring in 7 days', 'Expired', 'Inactive'];
  late Future<List<Json>> _future = _load();

  Future<List<Json>> _load() async {
    final r = await api('members');
    return (r['members'] as List).map((e) => Json.from(e)).toList();
  }

  void _reload() { if (mounted) setState(() => _future = _load()); }

  @override
  void initState() { super.initState(); refresh.addListener(_reload); }
  @override
  void dispose() { refresh.removeListener(_reload); super.dispose(); }

  bool _match(Json m) {
    final active = m['active'] == true;
    final left = daysLeft(DateTime.parse(m['expiry_date']));
    final q = _q.toLowerCase();
    if (q.isNotEmpty && !('${m['name']}'.toLowerCase().contains(q) || '${m['phone']}'.contains(q))) {
      return false;
    }
    switch (_f) {
      case 'Inactive': return !active;
      case 'Unpaid': return active && m['status'] == 'unpaid';
      case 'Expiring in 7 days': return active && left >= 0 && left <= 7;
      case 'Expired': return active && left < 0;
      default: return active;
    }
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  /// Run an API action, then reload; show errors as a snackbar.
  Future<void> _do(Future<void> Function() f) async {
    try {
      await f();
      _reload();
    } on ApiError catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _checkIn(Json m) => _do(() async {
        final r = await api('checkin', body: {'id': m['id']});
        _snack(r['expired'] == true
            ? '${m['name']} checked in - MEMBERSHIP EXPIRED'
            : '${m['name']} checked in');
      });

  Future<void> _markPaid(Json m) async {
    final r = await payDialog(context, 'Record payment');
    if (r == null) return;
    await _do(() => api('member_pay', body: {'id': m['id'], 'amount': r['amount'], 'method': r['method']}));
  }

  Future<void> _renew(Json m) async {
    final r = await payDialog(context, 'Renew membership', withMonths: true);
    if (r == null) return;
    await _do(() => api('member_renew',
        body: {'id': m['id'], 'months': r['months'], 'amount': r['amount'], 'method': r['method']}));
  }

  Future<void> _edit(Json m) async {
    final name = TextEditingController(text: m['name']);
    final addr = TextEditingController(text: m['address']);
    final phone = TextEditingController(text: m['phone']);
    final bday = TextEditingController(text: m['birthday'] ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit member'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: addr, decoration: const InputDecoration(labelText: 'Address')),
            TextField(
              controller: phone,
              decoration: const InputDecoration(labelText: 'WhatsApp number', helperText: 'Login ID stays the same'),
            ),
            TextField(controller: bday, decoration: const InputDecoration(labelText: 'Birthday (MM-DD, optional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    await _do(() => api('member_update', body: {
          'id': m['id'], 'name': name.text.trim(), 'address': addr.text.trim(),
          'phone': phone.text.trim(), 'birthday': bday.text.trim(),
        }));
  }

  Future<void> _resetPw(Json m) async {
    try {
      final r = await api('member_reset', body: {'id': m['id']});
      if (mounted) showCreds(context, r['login_id'], r['password'], title: 'New password');
    } on ApiError catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _export() async {
    try {
      final r = await api('export_token');
      final uri = Uri.parse(apiBase).replace(queryParameters: {'r': 'export', 'token': r['token']});
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on ApiError catch (e) {
      _snack(e.message);
    }
  }

  DataRow _row(Json m) {
    final exp = DateTime.parse(m['expiry_date']);
    final left = daysLeft(exp);
    final paid = m['status'] == 'paid';
    final active = m['active'] == true;
    return DataRow(cells: [
      DataCell(Text(m['name'] ?? '')),
      DataCell(Text(m['phone'] ?? '')),
      DataCell(Text(m['address'] ?? '')),
      DataCell(Text('${m['duration_months']} mo')),
      DataCell(Text(fmt.format(exp))),
      DataCell(Text(left < 0 ? 'Expired' : '$left',
          style: TextStyle(fontWeight: FontWeight.bold, color: left <= 2 ? Colors.red : Colors.green[700]))),
      DataCell(Chip(
        label: Text(paid ? 'Paid' : 'Unpaid'),
        backgroundColor: paid ? Colors.green[100] : Colors.red[100],
      )),
      DataCell(PopupMenuButton<String>(
        onSelected: (v) {
          switch (v) {
            case 'in': _checkIn(m); break;
            case 'paid': _markPaid(m); break;
            case 'renew': _renew(m); break;
            case 'edit': _edit(m); break;
            case 'pw': _resetPw(m); break;
            case 'active': _do(() => api('member_active', body: {'id': m['id'], 'active': !active})); break;
          }
        },
        itemBuilder: (_) => [
          if (active) const PopupMenuItem(value: 'in', child: Text('Check-in')),
          if (!paid) const PopupMenuItem(value: 'paid', child: Text('Mark paid')),
          const PopupMenuItem(value: 'renew', child: Text('Renew')),
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          const PopupMenuItem(value: 'pw', child: Text('Reset password')),
          PopupMenuItem(value: 'active', child: Text(active ? 'Deactivate' : 'Reactivate')),
        ],
      )),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search), hintText: 'Search name or phone', border: OutlineInputBorder()),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
          IconButton(tooltip: 'Download Excel (CSV)', icon: const Icon(Icons.download), onPressed: _export),
        ]),
      ),
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: _filters
              .map((f) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(f), selected: _f == f, onSelected: (_) => setState(() => _f = f)),
                  ))
              .toList(),
        ),
      ),
      Expanded(
        child: loadView<List<Json>>(_future, (all) {
          final rows = all.where(_match).toList();
          if (rows.isEmpty) return const Center(child: Text('No members found'));
          return SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Name')),
                  DataColumn(label: Text('Phone')),
                  DataColumn(label: Text('Address')),
                  DataColumn(label: Text('Plan')),
                  DataColumn(label: Text('Expiry')),
                  DataColumn(label: Text('Days Left')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('')),
                ],
                rows: rows.map(_row).toList(),
              ),
            ),
          );
        }),
      ),
    ]);
  }
}

// ----------------------------------------------------------------- NEW MEMBER
class AddMemberPage extends StatefulWidget {
  const AddMemberPage({super.key});
  @override
  State<AddMemberPage> createState() => _AddMemberPageState();
}

class _AddMemberPageState extends State<AddMemberPage> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController(text: '977'); // country code, no "+"
  final _bday = TextEditingController();
  final _amount = TextEditingController();
  int _months = 1;
  String _status = 'unpaid', _method = methods.first;
  late DateTime _expiry = addMonths(dateOnly(DateTime.now()), _months);
  bool _saving = false;

  Future<void> _pickExpiry() async {
    final p = await showDatePicker(
        context: context,
        initialDate: _expiry,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 1500)));
    if (p != null) setState(() => _expiry = p);
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final r = await api('member_create', body: {
        'name': _name.text.trim(),
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
        'birthday': _bday.text.trim(),
        'duration_months': _months,
        'expiry_date': ymd(_expiry),
        'status': _status,
        'amount': int.tryParse(_amount.text.trim()) ?? 0,
        'method': _method,
      });
      if (mounted) Navigator.pop(context, Json.from(r));
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Member')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _key,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) => v!.trim().isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Address'),
                validator: (v) => v!.trim().isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'WhatsApp number (with country code)',
                    helperText: "This number becomes the member's login ID"),
                validator: (v) => RegExp(r'^\d{10,15}$').hasMatch(v!.trim()) ? null : 'Digits only, with country code',
              ),
              TextFormField(
                controller: _bday,
                decoration: const InputDecoration(labelText: 'Birthday (MM-DD, optional)', helperText: 'e.g. 03-25'),
                validator: (v) =>
                    v!.trim().isEmpty || RegExp(r'^\d{2}-\d{2}$').hasMatch(v.trim()) ? null : 'Use MM-DD',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _months,
                decoration: const InputDecoration(labelText: 'Membership duration'),
                items: [1, 3, 6, 12].map((m) => DropdownMenuItem(value: m, child: Text('$m month(s)'))).toList(),
                onChanged: (v) => setState(() {
                  _months = v!;
                  _expiry = addMonths(dateOnly(DateTime.now()), _months);
                }),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Expiry date'),
                subtitle: Text(fmt.format(_expiry)),
                trailing: const Icon(Icons.calendar_today),
                onTap: _pickExpiry,
              ),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Plan status'),
                items: const [
                  DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
                  DropdownMenuItem(value: 'paid', child: Text('Paid')),
                ],
                onChanged: (v) => setState(() => _status = v!),
              ),
              if (_status == 'paid') ...[
                TextFormField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount paid (Rs)'),
                ),
                DropdownButtonFormField<String>(
                  value: _method,
                  decoration: const InputDecoration(labelText: 'Payment method'),
                  items: methods.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) => setState(() => _method = v!),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
