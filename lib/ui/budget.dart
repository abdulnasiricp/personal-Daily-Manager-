import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../calc.dart';
import '../db.dart';
import 'common.dart';

const expenseCategories = [
  'Food', 'Transport', 'Bills', 'Rent', 'Shopping', 'Health',
  'Education', 'Family', 'Entertainment', 'Other'
];
const incomeCategories = ['Salary', 'Business', 'Gift', 'Other'];

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});
  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> with Refreshable<BudgetPage> {
  String _mode = 'day';
  DateTime _anchor = DateTime.now();
  List<Txn> _items = [];
  int _income = 0, _expense = 0, _budget = 0;
  bool _loaded = false;

  Range get _range =>
      _mode == 'day' ? dayRange(_anchor) : (_mode == 'week' ? weekRange(_anchor) : monthRange(_anchor));

  @override
  Future<void> reload() async {
    final db = AppDb.instance;
    final r = _range;
    final items = await db.txns(r);
    final t = await db.totals(r);
    final b = await db.budgetFor(monthKey(_anchor));
    if (!mounted) return;
    setState(() {
      _items = items;
      _income = t.income;
      _expense = t.expense;
      _budget = b;
      _loaded = true;
    });
  }

  void _shift(int dir) {
    final a = _anchor;
    setState(() {
      if (_mode == 'day') {
        _anchor = DateTime(a.year, a.month, a.day + dir);
      } else if (_mode == 'week') {
        _anchor = DateTime(a.year, a.month, a.day + 7 * dir);
      } else {
        _anchor = DateTime(a.year, a.month + dir, 1);
      }
    });
    reload();
  }

  String get _label {
    final r = _range;
    if (_mode == 'day') return fmtDate(r.start);
    if (_mode == 'week') {
      final last = DateTime(r.end.year, r.end.month, r.end.day - 1);
      return '${DateFormat('d MMM').format(r.start)} - ${DateFormat('d MMM yyyy').format(last)}';
    }
    return DateFormat('MMMM yyyy').format(r.start);
  }

  Future<void> _setBudget() async {
    final month = monthKey(_anchor);
    final ctrl = TextEditingController(text: _budget == 0 ? '' : moneyInput(_budget));
    final key = GlobalKey<FormState>();
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Budget for ${DateFormat('MMMM yyyy').format(_anchor)}'),
        content: Form(
          key: key,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Monthly budget', prefixText: 'PKR '),
            validator: (v) => parseMoney(v ?? '') == null ? 'Enter a valid amount' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) Navigator.pop(ctx, parseMoney(ctrl.text));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      await AppDb.instance.setBudget(month, result);
      if (mounted) toast(context, 'Budget saved. It also applies to later months until you change it.');
    }
  }

  Future<void> _history() async {
    final m = await Navigator.push<DateTime>(
        context, MaterialPageRoute(builder: (_) => const HistoryPage()));
    if (m != null) {
      setState(() {
        _mode = 'month';
        _anchor = m;
      });
      reload();
    }
  }

  Future<void> _delete(Txn t) async {
    if (await confirm(context, 'Delete transaction?',
        '${t.category} ${formatMoney(t.amount)} will be permanently deleted.')) {
      await AppDb.instance.deleteTxn(t.id!);
      if (mounted) toast(context, 'Transaction deleted');
    }
  }

  Widget _tile(Txn t) {
    final color = t.isIncome ? incomeColor : expenseColor;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => showForm(context, TxnForm(txn: t)),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(t.isIncome ? Icons.arrow_downward : Icons.arrow_upward, color: color),
        ),
        title: Text(t.category),
        subtitle: Text([if (t.description.isNotEmpty) t.description, fmtDateTime(t.when)].join('\n')),
        isThreeLine: t.description.isNotEmpty,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${t.isIncome ? '+' : '-'}${formatMoney(t.amount)}',
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          IconButton(
              icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: () => _delete(t)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final remaining = _budget - _expense;
    return Scaffold(
      appBar: AppBar(title: const Text('Budget & Expenses'), actions: [
        IconButton(tooltip: 'Set monthly budget', icon: const Icon(Icons.savings_outlined), onPressed: _setBudget),
        IconButton(tooltip: 'Previous months', icon: const Icon(Icons.history), onPressed: _history),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showForm(context, const TxnForm()),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'day', label: Text('Daily')),
                  ButtonSegment(value: 'week', label: Text('Weekly')),
                  ButtonSegment(value: 'month', label: Text('Monthly')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) {
                  setState(() => _mode = s.first);
                  reload();
                },
              ),
              Row(children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
                Expanded(
                    child: Text(_label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium)),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
              ]),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Stat(label: 'Income', value: formatMoney(_income), color: incomeColor)),
                      Expanded(child: Stat(label: 'Expenses', value: formatMoney(_expense), color: expenseColor)),
                      Expanded(
                          child: Stat(
                              label: 'Net',
                              value: formatMoney(_income - _expense),
                              color: _income - _expense < 0 ? cs.error : null)),
                    ]),
                    if (_mode == 'month') ...[
                      const Divider(height: 24),
                      if (_budget == 0)
                        const Text('No budget set for this month. Tap the piggy bank icon above.')
                      else ...[
                        Row(children: [
                          Expanded(child: Stat(label: 'Budget', value: formatMoney(_budget))),
                          Expanded(
                              child: Stat(
                                  label: 'Budget remaining',
                                  value: formatMoney(remaining),
                                  color: remaining < 0 ? cs.error : incomeColor)),
                        ]),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: (_expense / _budget).clamp(0.0, 1.0),
                          minHeight: 8,
                          color: remaining < 0 ? cs.error : null,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ],
                  ]),
                ),
              ),
              const SectionTitle('Transactions'),
              if (_items.isEmpty)
                const EmptyState(icon: Icons.receipt_long_outlined, message: 'No transactions in this period.')
              else
                ..._items.map(_tile),
            ]),
    );
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<MapEntry<String, MonthSummary>>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDb.instance;
    final rows = <MapEntry<String, MonthSummary>>[];
    for (final m in await db.historyMonths()) {
      rows.add(MapEntry(m, await db.monthSummary(DateTime.parse('$m-01'))));
    }
    if (mounted) setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly history')),
      body: _rows == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              for (final e in _rows!)
                Card(
                  child: InkWell(
                    onTap: () => Navigator.pop(context, DateTime.parse('${e.key}-01')),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(DateFormat('MMMM yyyy').format(DateTime.parse('${e.key}-01')),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: Stat(label: 'Income', value: formatMoney(e.value.income), color: incomeColor)),
                          Expanded(child: Stat(label: 'Expenses', value: formatMoney(e.value.expense), color: expenseColor)),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: Stat(label: 'Budget', value: e.value.budget == 0 ? 'Not set' : formatMoney(e.value.budget))),
                          Expanded(
                              child: Stat(
                                  label: 'Budget remaining',
                                  value: e.value.budget == 0 ? '-' : formatMoney(e.value.remainingBudget),
                                  color: e.value.remainingBudget < 0 && e.value.budget > 0 ? cs.error : null)),
                        ]),
                      ]),
                    ),
                  ),
                ),
            ]),
    );
  }
}

class TxnForm extends StatefulWidget {
  final Txn? txn;
  const TxnForm({super.key, this.txn});
  @override
  State<TxnForm> createState() => _TxnFormState();
}

class _TxnFormState extends State<TxnForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _amount =
      TextEditingController(text: widget.txn == null ? '' : moneyInput(widget.txn!.amount));
  late final TextEditingController _desc = TextEditingController(text: widget.txn?.description ?? '');
  late String _type = widget.txn?.type ?? 'expense';
  late String _category = widget.txn?.category ?? 'Food';
  late DateTime _when = widget.txn?.when ?? DateTime.now();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  List<String> get _cats {
    final base = _type == 'income' ? incomeCategories : expenseCategories;
    return base.contains(_category) ? base : [...base, _category];
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final t = Txn(
      id: widget.txn?.id,
      type: _type,
      amount: parseMoney(_amount.text)!,
      category: _category,
      description: _desc.text.trim(),
      at: isoLocal(_when),
    );
    try {
      if (t.id == null) {
        await AppDb.instance.insertTxn(t);
      } else {
        await AppDb.instance.updateTxn(t);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = 'Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.txn == null ? 'New transaction' : 'Edit transaction',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'expense', label: Text('Expense'), icon: Icon(Icons.arrow_upward)),
            ButtonSegment(value: 'income', label: Text('Income'), icon: Icon(Icons.arrow_downward)),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() {
            _type = s.first;
            _category = _type == 'income' ? incomeCategories.first : expenseCategories.first;
          }),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _amount,
          autofocus: widget.txn == null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount', prefixText: 'PKR '),
          validator: (v) {
            final a = parseMoney(v ?? '');
            if (a == null) return 'Enter a valid amount (e.g. 1500 or 1500.50)';
            if (a <= 0) return 'Amount must be greater than zero';
            return null;
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: _cats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _desc,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Description (optional)'),
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
                    context: context,
                    initialDate: _when,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100));
                if (d != null) {
                  setState(() => _when = DateTime(d.year, d.month, d.day, _when.hour, _when.minute));
                }
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
                final t = await showTimePicker(
                    context: context, initialTime: TimeOfDay.fromDateTime(_when));
                if (t != null) {
                  setState(() => _when = DateTime(_when.year, _when.month, _when.day, t.hour, t.minute));
                }
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
        FilledButton(onPressed: _save, child: const Text('Save')),
      ]),
    );
  }
}
