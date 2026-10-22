import 'package:flutter/material.dart';

import '../calc.dart';
import '../db.dart';
import 'common.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with Refreshable<DashboardPage> {
  bool _loaded = false;
  int _done = 0, _total = 0, _overdue = 0;
  int _income = 0, _expense = 0;
  int _borrowed = 0, _lent = 0;
  MonthSummary _month = const MonthSummary(0, 0, 0);
  List<AgendaItem> _upcoming = [];

  @override
  Future<void> reload() async {
    final db = AppDb.instance;
    final now = DateTime.now();
    final prog = await db.taskProgress(now);
    final od = await db.overdueTaskCount(now);
    final today = await db.totals(dayRange(now));
    final month = await db.monthSummary(now);
    final borrowed = await db.outstandingTotal('borrowed');
    final lent = await db.outstandingTotal('lent');
    final up = await db.agenda(now);
    if (!mounted) return;
    setState(() {
      _done = prog.done;
      _total = prog.total;
      _overdue = od;
      _income = today.income;
      _expense = today.expense;
      _month = month;
      _borrowed = borrowed;
      _lent = lent;
      _upcoming = up.take(5).toList();
      _loaded = true;
    });
  }

  IconData _icon(String kind) {
    switch (kind) {
      case 'task':
        return Icons.checklist;
      case 'bill':
        return Icons.receipt_long;
      case 'loan':
        return Icons.handshake;
      default:
        return Icons.notifications_active;
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cs = Theme.of(context).colorScheme;
    final remaining = _month.remainingBudget;
    return Scaffold(
      appBar: AppBar(title: const Text('Personal Daily Manager')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                InfoCard(
                  title: fmtDate(now),
                  icon: Icons.today,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_total == 0 ? 'No tasks planned for today' : '$_done of $_total tasks done today',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _total == 0 ? 0 : _done / _total,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    if (_overdue > 0) ...[
                      const SizedBox(height: 8),
                      Text('$_overdue overdue task${_overdue == 1 ? '' : 's'}',
                          style: TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
                    ],
                  ]),
                ),
                InfoCard(
                  title: 'Today',
                  icon: Icons.swap_vert,
                  child: Row(children: [
                    Expanded(child: Stat(label: 'Income', value: formatMoney(_income), color: incomeColor)),
                    Expanded(child: Stat(label: 'Expenses', value: formatMoney(_expense), color: expenseColor)),
                  ]),
                ),
                InfoCard(
                  title: 'This month\'s budget',
                  icon: Icons.account_balance_wallet,
                  child: _month.budget == 0
                      ? const Text('No budget set. Open the Budget tab and tap the piggy bank icon.')
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Stat(label: 'Budget', value: formatMoney(_month.budget))),
                            Expanded(child: Stat(label: 'Spent', value: formatMoney(_month.expense), color: expenseColor)),
                            Expanded(
                                child: Stat(
                                    label: 'Remaining',
                                    value: formatMoney(remaining),
                                    color: remaining < 0 ? cs.error : incomeColor)),
                          ]),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: (_month.expense / _month.budget).clamp(0.0, 1.0),
                            minHeight: 8,
                            color: remaining < 0 ? cs.error : null,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ]),
                ),
                InfoCard(
                  title: 'Udhaar (outstanding)',
                  icon: Icons.handshake,
                  child: Row(children: [
                    Expanded(child: Stat(label: 'I owe', value: formatMoney(_borrowed), color: _borrowed > 0 ? expenseColor : null)),
                    Expanded(child: Stat(label: 'Owed to me', value: formatMoney(_lent), color: _lent > 0 ? incomeColor : null)),
                  ]),
                ),
                InfoCard(
                  title: 'Upcoming reminders',
                  icon: Icons.notifications,
                  child: _upcoming.isEmpty
                      ? const Text('Nothing coming up.')
                      : Column(
                          children: _upcoming
                              .map((a) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    leading: Icon(_icon(a.kind)),
                                    title: Text(a.title),
                                    subtitle: Text(a.kind == 'loan' ? fmtDate(a.when) : fmtDateTime(a.when)),
                                  ))
                              .toList(),
                        ),
                ),
              ],
            ),
    );
  }
}
