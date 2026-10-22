import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../calc.dart';
import '../db.dart';
import '../notifications.dart';
import 'common.dart';

class LoansPage extends StatelessWidget {
  const LoansPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Udhaar (Loans)'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Borrowed (I owe)'),
            Tab(text: 'Lent (owed to me)'),
          ]),
        ),
        floatingActionButton: Builder(builder: (ctx) {
          final c = DefaultTabController.of(ctx);
          return AnimatedBuilder(
            animation: c,
            builder: (_, __) => FloatingActionButton.extended(
              onPressed: () => showForm(ctx, LoanForm(direction: c.index == 0 ? 'borrowed' : 'lent')),
              icon: const Icon(Icons.add),
              label: Text(c.index == 0 ? 'I borrowed' : 'I lent'),
            ),
          );
        }),
        body: const TabBarView(children: [
          LoanList(direction: 'borrowed'),
          LoanList(direction: 'lent'),
        ]),
      ),
    );
  }
}

class LoanList extends StatefulWidget {
  final String direction;
  const LoanList({super.key, required this.direction});
  @override
  State<LoanList> createState() => _LoanListState();
}

class _LoanListState extends State<LoanList> with Refreshable<LoanList> {
  List<Loan> _loans = [];
  bool _loaded = false;

  @override
  Future<void> reload() async {
    final l = await AppDb.instance.loans(widget.direction);
    if (!mounted) return;
    setState(() {
      _loans = l;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final lent = widget.direction == 'lent';
    final total = _loans.fold<int>(0, (s, l) => s + (l.outstanding > 0 ? l.outstanding : 0));
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
      Card(
        color: cs.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Stat(label: lent ? 'Total owed to me' : 'Total I owe', value: formatMoney(total)),
        ),
      ),
      const SizedBox(height: 8),
      if (_loans.isEmpty)
        EmptyState(
            icon: Icons.handshake_outlined,
            message: lent ? 'No money lent yet.\nTap "I lent" to record one.' : 'No money borrowed yet.\nTap "I borrowed" to record one.')
      else
        ..._loans.map((l) {
          final overdue = isOverdue(l.dueDate, l.outstanding, now);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => LoanDetailPage(loanId: l.id!))),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                        child: Text(l.person,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                    if (overdue)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(8)),
                        child: Text('OVERDUE',
                            style: TextStyle(color: cs.onErrorContainer, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  Text(l.settled ? 'Settled' : 'Outstanding: ${formatMoney(l.outstanding)}',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: l.settled ? incomeColor : (lent ? incomeColor : expenseColor))),
                  Text('Total ${formatMoney(l.amount)}  -  Repaid ${formatMoney(l.repaid)}'),
                  if (l.dueDate != null)
                    Text('Expected repayment: ${fmtDate(DateTime.parse(l.dueDate!))}',
                        style: TextStyle(color: overdue ? cs.error : null)),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (l.repaid / l.amount).clamp(0.0, 1.0),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ]),
              ),
            ),
          );
        }),
    ]);
  }
}

class LoanDetailPage extends StatefulWidget {
  final int loanId;
  const LoanDetailPage({super.key, required this.loanId});
  @override
  State<LoanDetailPage> createState() => _LoanDetailPageState();
}

class _LoanDetailPageState extends State<LoanDetailPage> with Refreshable<LoanDetailPage> {
  Loan? _loan;
  List<Repayment> _reps = [];
  bool _loaded = false;

  @override
  Future<void> reload() async {
    final l = await AppDb.instance.loan(widget.loanId);
    final r = l == null ? <Repayment>[] : await AppDb.instance.repayments(widget.loanId);
    if (!mounted) return;
    if (l == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _loan = l;
      _reps = r;
      _loaded = true;
    });
  }

  Future<void> _deleteLoan() async {
    final l = _loan!;
    final ok = await confirm(context, 'Delete this loan?',
        'The loan with ${l.person} and all ${_reps.length} repayment record(s) will be permanently deleted.');
    if (ok) {
      await AppDb.instance.deleteLoan(l.id!);
    }
  }

  Future<void> _deleteRepayment(Repayment r) async {
    if (await confirm(context, 'Delete repayment?',
        'The repayment of ${formatMoney(r.amount)} will be removed and the outstanding balance will increase.')) {
      await AppDb.instance.deleteRepayment(r.id!);
    }
  }

  Future<void> _markPaid() async {
    final l = _loan!;
    if (await confirm(context, 'Mark as fully paid?',
        'A repayment of ${formatMoney(l.outstanding)} will be recorded today.',
        yes: 'Confirm')) {
      try {
        await AppDb.instance.addRepayment(l.id!, l.outstanding, DateTime.now(), 'Final payment');
      } on AppException catch (e) {
        if (mounted) toast(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final l = _loan!;
    final lent = l.direction == 'lent';
    final cs = Theme.of(context).colorScheme;
    final overdue = isOverdue(l.dueDate, l.outstanding, DateTime.now());
    return Scaffold(
      appBar: AppBar(title: Text(l.person), actions: [
        IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showForm(context, LoanForm(direction: l.direction, loan: l))),
        IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _deleteLoan),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lent ? 'You lent money' : 'You borrowed money',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Stat(label: 'Original amount', value: formatMoney(l.amount))),
                Expanded(child: Stat(label: 'Repaid', value: formatMoney(l.repaid))),
              ]),
              const SizedBox(height: 12),
              Stat(
                  label: 'Outstanding',
                  value: l.settled ? 'Settled' : formatMoney(l.outstanding),
                  color: l.settled ? incomeColor : (lent ? incomeColor : expenseColor)),
              const SizedBox(height: 12),
              Text('Date: ${fmtDateTime(l.when)}'),
              if (l.dueDate != null)
                Text('Expected repayment: ${fmtDate(DateTime.parse(l.dueDate!))}${overdue ? '  (OVERDUE)' : ''}',
                    style: TextStyle(color: overdue ? cs.error : null, fontWeight: overdue ? FontWeight.w700 : null)),
              if (l.phone.isNotEmpty) Text('Phone: ${l.phone}'),
              if (l.note.isNotEmpty) Text('Note: ${l.note}'),
              const SizedBox(height: 8),
              Text(
                  'This loan is kept separate from your income and expenses.',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        if (!l.settled)
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => showForm(context, RepaymentForm(loan: l)),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Add repayment'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _markPaid,
                icon: const Icon(Icons.done_all),
                label: const Text('Mark fully paid'),
              ),
            ),
          ]),
        const SectionTitle('Repayment history'),
        if (_reps.isEmpty)
          const EmptyState(icon: Icons.history, message: 'No repayments recorded yet.')
        else
          ..._reps.map((r) => Card(
                child: ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: Text(formatMoney(r.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([fmtDateTime(r.when), if (r.note.isNotEmpty) r.note].join('\n')),
                  isThreeLine: r.note.isNotEmpty,
                  trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () => _deleteRepayment(r)),
                ),
              )),
      ]),
    );
  }
}

class RepaymentForm extends StatefulWidget {
  final Loan loan;
  const RepaymentForm({super.key, required this.loan});
  @override
  State<RepaymentForm> createState() => _RepaymentFormState();
}

class _RepaymentFormState extends State<RepaymentForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _amount = TextEditingController(text: moneyInput(widget.loan.outstanding));
  final TextEditingController _note = TextEditingController();
  DateTime _when = DateTime.now();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    try {
      await AppDb.instance.addRepayment(widget.loan.id!, parseMoney(_amount.text)!, _when, _note.text.trim());
      if (mounted) Navigator.pop(context);
    } on AppException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Add repayment', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Outstanding: ${formatMoney(widget.loan.outstanding)}'),
        const SizedBox(height: 16),
        TextFormField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount', prefixText: 'PKR '),
          validator: (v) {
            final a = parseMoney(v ?? '');
            if (a == null || a <= 0) return 'Enter a valid amount';
            if (a > widget.loan.outstanding) return 'More than the outstanding balance';
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: PickTile(
              icon: Icons.calendar_today,
              label: 'Date',
              value: DateFormat('d MMM yyyy').format(_when),
              onTap: () async {
                final d = await showDatePicker(
                    context: context, initialDate: _when, firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (d != null) setState(() => _when = DateTime(d.year, d.month, d.day, _when.hour, _when.minute));
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PickTile(
              icon: Icons.access_time,
              label: 'Time',
              value: fmtTime(_when),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
                if (t != null) setState(() => _when = DateTime(_when.year, _when.month, _when.day, t.hour, t.minute));
              },
            ),
          ),
        ]),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('Save repayment')),
      ]),
    );
  }
}

class LoanForm extends StatefulWidget {
  final String direction;
  final Loan? loan;
  const LoanForm({super.key, required this.direction, this.loan});
  @override
  State<LoanForm> createState() => _LoanFormState();
}

class _LoanFormState extends State<LoanForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _person = TextEditingController(text: widget.loan?.person ?? '');
  late final TextEditingController _phone = TextEditingController(text: widget.loan?.phone ?? '');
  late final TextEditingController _amount =
      TextEditingController(text: widget.loan == null ? '' : moneyInput(widget.loan!.amount));
  late final TextEditingController _note = TextEditingController(text: widget.loan?.note ?? '');
  late DateTime _when = widget.loan?.when ?? DateTime.now();
  DateTime? _due;
  String? _error;

  @override
  void initState() {
    super.initState();
    final d = widget.loan?.dueDate;
    if (d != null) _due = DateTime.parse(d);
  }

  @override
  void dispose() {
    _person.dispose();
    _phone.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final old = widget.loan;
    final l = Loan(
      id: old?.id,
      direction: widget.direction,
      person: _person.text.trim(),
      phone: _phone.text.trim(),
      amount: parseMoney(_amount.text)!,
      at: isoLocal(_when),
      dueDate: _due == null ? null : dateKey(_due!),
      note: _note.text.trim(),
    );
    try {
      if (l.id == null) {
        await AppDb.instance.insertLoan(l);
      } else {
        await AppDb.instance.updateLoan(l);
      }
      if (_due != null) await Notifier.ensurePermission();
      if (mounted) Navigator.pop(context);
    } on AppException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lent = widget.direction == 'lent';
    return Form(
      key: _key,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
            widget.loan == null
                ? (lent ? 'Money I lent' : 'Money I borrowed')
                : 'Edit loan',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextFormField(
          controller: _person,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: lent ? 'Lent to (name)' : 'Borrowed from (name)'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone number (optional)'),
          validator: (v) {
            final s = (v ?? '').trim();
            if (s.isEmpty) return null;
            return RegExp(r'^\+?[0-9 \-]{7,15}$').hasMatch(s) ? null : 'Enter a valid phone number';
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount', prefixText: 'PKR '),
          validator: (v) {
            final a = parseMoney(v ?? '');
            if (a == null || a <= 0) return 'Enter a valid amount greater than zero';
            return null;
          },
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: PickTile(
              icon: Icons.calendar_today,
              label: 'Date',
              value: DateFormat('d MMM yyyy').format(_when),
              onTap: () async {
                final d = await showDatePicker(
                    context: context, initialDate: _when, firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (d != null) setState(() => _when = DateTime(d.year, d.month, d.day, _when.hour, _when.minute));
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PickTile(
              icon: Icons.access_time,
              label: 'Time',
              value: fmtTime(_when),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
                if (t != null) setState(() => _when = DateTime(_when.year, _when.month, _when.day, t.hour, t.minute));
              },
            ),
          ),
        ]),
        const SizedBox(height: 12),
        PickTile(
          icon: Icons.event,
          label: 'Expected repayment date (optional)',
          value: _due == null ? 'Not set' : fmtDate(_due!),
          onTap: () async {
            final d = await showDatePicker(
                context: context,
                initialDate: _due ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100));
            if (d != null) setState(() => _due = d);
          },
          onClear: _due == null ? null : () => setState(() => _due = null),
        ),
        const SizedBox(height: 12),
        TextFormField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ]),
    );
  }
}
