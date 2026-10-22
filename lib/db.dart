import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'backup.dart';
import 'calc.dart';

// ------------------------------------------------------------------ models

class Task {
  final int? id;
  final String title;
  final String notes;
  final String dueDate; // yyyy-MM-dd
  final String? dueTime; // HH:mm
  final int priority; // 0 low, 1 medium, 2 high
  final bool done;
  final String? doneAt;
  final bool remind;
  const Task({
    this.id,
    required this.title,
    this.notes = '',
    required this.dueDate,
    this.dueTime,
    this.priority = 1,
    this.done = false,
    this.doneAt,
    this.remind = false,
  });

  factory Task.fromMap(Map<String, Object?> m) => Task(
        id: m['id'] as int,
        title: m['title'] as String,
        notes: (m['notes'] as String?) ?? '',
        dueDate: m['due_date'] as String,
        dueTime: m['due_time'] as String?,
        priority: m['priority'] as int,
        done: (m['done'] as int) == 1,
        doneAt: m['done_at'] as String?,
        remind: (m['remind'] as int) == 1,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'title': title,
        'notes': notes,
        'due_date': dueDate,
        'due_time': dueTime,
        'priority': priority,
        'done': done ? 1 : 0,
        'done_at': doneAt,
        'remind': remind ? 1 : 0,
      };

  DateTime? get dueAt => dueTime == null ? null : combine(dueDate, dueTime);
}

class Txn {
  final int? id;
  final String type; // income | expense
  final int amount; // paisa
  final String category;
  final String description;
  final String at; // yyyy-MM-ddTHH:mm:ss
  const Txn({
    this.id,
    required this.type,
    required this.amount,
    required this.category,
    this.description = '',
    required this.at,
  });

  factory Txn.fromMap(Map<String, Object?> m) => Txn(
        id: m['id'] as int,
        type: m['type'] as String,
        amount: m['amount'] as int,
        category: m['category'] as String,
        description: (m['description'] as String?) ?? '',
        at: m['at'] as String,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'type': type,
        'amount': amount,
        'category': category,
        'description': description,
        'at': at,
      };

  DateTime get when => DateTime.parse(at);
  bool get isIncome => type == 'income';
}

class Loan {
  final int? id;
  final String direction; // borrowed | lent
  final String person;
  final String phone;
  final int amount; // principal, paisa
  final String at;
  final String? dueDate;
  final String note;
  final int repaid; // sum of repayments, paisa
  const Loan({
    this.id,
    required this.direction,
    required this.person,
    this.phone = '',
    required this.amount,
    required this.at,
    this.dueDate,
    this.note = '',
    this.repaid = 0,
  });

  factory Loan.fromMap(Map<String, Object?> m) => Loan(
        id: m['id'] as int,
        direction: m['direction'] as String,
        person: m['person'] as String,
        phone: (m['phone'] as String?) ?? '',
        amount: m['amount'] as int,
        at: m['at'] as String,
        dueDate: m['due_date'] as String?,
        note: (m['note'] as String?) ?? '',
        repaid: (m['repaid'] as int?) ?? 0,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'direction': direction,
        'person': person,
        'phone': phone,
        'amount': amount,
        'at': at,
        'due_date': dueDate,
        'note': note,
      };

  int get outstanding => amount - repaid;
  bool get settled => outstanding <= 0;
  DateTime get when => DateTime.parse(at);
}

class Repayment {
  final int? id;
  final int loanId;
  final int amount;
  final String at;
  final String note;
  const Repayment({this.id, required this.loanId, required this.amount, required this.at, this.note = ''});

  factory Repayment.fromMap(Map<String, Object?> m) => Repayment(
        id: m['id'] as int,
        loanId: m['loan_id'] as int,
        amount: m['amount'] as int,
        at: m['at'] as String,
        note: (m['note'] as String?) ?? '',
      );
  DateTime get when => DateTime.parse(at);
}

class Reminder {
  final int? id;
  final String title;
  final String notes;
  final String at;
  final String repeat; // none | daily | weekly | monthly
  final String kind; // general | bill
  final bool active;
  const Reminder({
    this.id,
    required this.title,
    this.notes = '',
    required this.at,
    this.repeat = 'none',
    this.kind = 'general',
    this.active = true,
  });

  factory Reminder.fromMap(Map<String, Object?> m) => Reminder(
        id: m['id'] as int,
        title: m['title'] as String,
        notes: (m['notes'] as String?) ?? '',
        at: m['at'] as String,
        repeat: m['repeat_mode'] as String,
        kind: m['kind'] as String,
        active: (m['active'] as int) == 1,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'title': title,
        'notes': notes,
        'at': at,
        'repeat_mode': repeat,
        'kind': kind,
        'active': active ? 1 : 0,
      };

  DateTime get when => DateTime.parse(at);
}

/// One upcoming notification-worthy item (reminder, task or loan due date).
class AgendaItem {
  final DateTime when;
  final String title;
  final String body;
  final String kind; // task | reminder | bill | loan
  const AgendaItem(this.when, this.title, this.body, this.kind);
}

// ------------------------------------------------------------------ schema

const _schema = <String>[
  '''CREATE TABLE tasks(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    notes TEXT NOT NULL DEFAULT '',
    due_date TEXT NOT NULL,
    due_time TEXT,
    priority INTEGER NOT NULL DEFAULT 1,
    done INTEGER NOT NULL DEFAULT 0,
    done_at TEXT,
    remind INTEGER NOT NULL DEFAULT 0)''',
  '''CREATE TABLE transactions(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL,
    amount INTEGER NOT NULL,
    category TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    at TEXT NOT NULL)''',
  'CREATE INDEX idx_txn_at ON transactions(at)',
  '''CREATE TABLE budgets(
    month TEXT PRIMARY KEY,
    amount INTEGER NOT NULL)''',
  '''CREATE TABLE loans(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    direction TEXT NOT NULL,
    person TEXT NOT NULL,
    phone TEXT NOT NULL DEFAULT '',
    amount INTEGER NOT NULL,
    at TEXT NOT NULL,
    due_date TEXT,
    note TEXT NOT NULL DEFAULT '')''',
  '''CREATE TABLE repayments(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    loan_id INTEGER NOT NULL,
    amount INTEGER NOT NULL,
    at TEXT NOT NULL,
    note TEXT NOT NULL DEFAULT '')''',
  '''CREATE TABLE reminders(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    notes TEXT NOT NULL DEFAULT '',
    at TEXT NOT NULL,
    repeat_mode TEXT NOT NULL DEFAULT 'none',
    kind TEXT NOT NULL DEFAULT 'general',
    active INTEGER NOT NULL DEFAULT 1)''',
  '''CREATE TABLE settings(
    name TEXT PRIMARY KEY,
    value TEXT NOT NULL)''',
];

// ------------------------------------------------------------------ database

class AppDb {
  AppDb();
  static final AppDb instance = AppDb();

  /// Incremented after every change so screens (and reminders) refresh.
  final ValueNotifier<int> version = ValueNotifier<int>(0);
  late Database _db;

  Future<void> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), 'daily_manager.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      singleInstance: false,
      onCreate: (db, v) async {
        for (final s in _schema) {
          await db.execute(s);
        }
      },
    );
  }

  Future<void> close() => _db.close();
  void _changed() => version.value++;

  // ---------------------------------------------------------------- settings

  Future<String?> getSetting(String name) async {
    final r = await _db.query('settings', where: 'name = ?', whereArgs: [name]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  Future<void> setSetting(String name, String value) async {
    await _db.insert('settings', {'name': name, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
    _changed();
  }

  // ---------------------------------------------------------------- tasks

  Future<int> insertTask(Task t) async {
    final id = await _db.insert('tasks', t.toMap());
    _changed();
    return id;
  }

  Future<void> updateTask(Task t) async {
    await _db.update('tasks', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
    _changed();
  }

  Future<void> deleteTask(int id) async {
    await _db.delete('tasks', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> setTaskDone(int id, bool done) async {
    await _db.update(
        'tasks', {'done': done ? 1 : 0, 'done_at': done ? isoLocal(DateTime.now()) : null},
        where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<List<Task>> tasks({required bool done}) async {
    final rows = await _db.query('tasks',
        where: 'done = ?',
        whereArgs: [done ? 1 : 0],
        orderBy: done
            ? 'done_at DESC, id DESC'
            : "due_date ASC, COALESCE(due_time, '99:99') ASC, priority DESC, id ASC");
    return rows.map(Task.fromMap).toList();
  }

  Future<({int done, int total})> taskProgress(DateTime day) async {
    final r = await _db.rawQuery(
        'SELECT COUNT(*) AS c, COALESCE(SUM(done), 0) AS d FROM tasks WHERE due_date = ?',
        [dateKey(day)]);
    return (done: r.first['d'] as int, total: r.first['c'] as int);
  }

  Future<int> overdueTaskCount(DateTime now) async {
    final r = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM tasks WHERE done = 0 AND due_date < ?', [dateKey(now)]);
    return r.first['c'] as int;
  }

  // ---------------------------------------------------------------- budget & transactions

  Future<int> insertTxn(Txn t) async {
    final id = await _db.insert('transactions', t.toMap());
    _changed();
    return id;
  }

  Future<void> updateTxn(Txn t) async {
    await _db.update('transactions', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
    _changed();
  }

  Future<void> deleteTxn(int id) async {
    await _db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<List<Txn>> txns(Range r) async {
    final rows = await _db.query('transactions',
        where: 'at >= ? AND at < ?',
        whereArgs: [isoLocal(r.start), isoLocal(r.end)],
        orderBy: 'at DESC, id DESC');
    return rows.map(Txn.fromMap).toList();
  }

  /// Income and expense totals in a range. Loans/repayments are NOT included.
  Future<({int income, int expense})> totals(Range r) async {
    final rows = await _db.rawQuery(
        'SELECT type, COALESCE(SUM(amount), 0) AS s FROM transactions '
        'WHERE at >= ? AND at < ? GROUP BY type',
        [isoLocal(r.start), isoLocal(r.end)]);
    var income = 0;
    var expense = 0;
    for (final row in rows) {
      if (row['type'] == 'income') income = row['s'] as int;
      if (row['type'] == 'expense') expense = row['s'] as int;
    }
    return (income: income, expense: expense);
  }

  Future<void> setBudget(String month, int amount) async {
    await _db.insert('budgets', {'month': month, 'amount': amount},
        conflictAlgorithm: ConflictAlgorithm.replace);
    _changed();
  }

  /// Budget of [month]; when none was set for that month, the most recent
  /// earlier budget carries forward. 0 when no budget was ever set.
  Future<int> budgetFor(String month) async {
    final r = await _db.query('budgets',
        columns: ['amount'],
        where: 'month <= ?',
        whereArgs: [month],
        orderBy: 'month DESC',
        limit: 1);
    return r.isEmpty ? 0 : r.first['amount'] as int;
  }

  Future<MonthSummary> monthSummary(DateTime d) async {
    final t = await totals(monthRange(d));
    final b = await budgetFor(monthKey(d));
    return MonthSummary(t.income, t.expense, b);
  }

  /// Month keys (yyyy-MM) that have data, newest first, always incl. current.
  Future<List<String>> historyMonths() async {
    final rows = await _db.rawQuery(
        'SELECT substr(at, 1, 7) AS m FROM transactions UNION SELECT month AS m FROM budgets');
    final set = rows.map((r) => r['m'] as String).toSet()..add(monthKey(DateTime.now()));
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  // ---------------------------------------------------------------- loans

  static const _loanSelect =
      'SELECT l.*, COALESCE((SELECT SUM(r.amount) FROM repayments r WHERE r.loan_id = l.id), 0) AS repaid FROM loans l';

  Future<int> insertLoan(Loan l) async {
    final id = await _db.insert('loans', l.toMap());
    _changed();
    return id;
  }

  Future<void> updateLoan(Loan l) async {
    final r = await _db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS s FROM repayments WHERE loan_id = ?', [l.id]);
    if (l.amount < (r.first['s'] as int)) {
      throw AppException(
          'The amount cannot be less than what has already been repaid (${formatMoney(r.first['s'] as int)}).');
    }
    await _db.update('loans', l.toMap(), where: 'id = ?', whereArgs: [l.id]);
    _changed();
  }

  Future<void> deleteLoan(int id) async {
    await _db.transaction((txn) async {
      await txn.delete('repayments', where: 'loan_id = ?', whereArgs: [id]);
      await txn.delete('loans', where: 'id = ?', whereArgs: [id]);
    });
    _changed();
  }

  Future<Loan?> loan(int id) async {
    final r = await _db.rawQuery('$_loanSelect WHERE l.id = ?', [id]);
    return r.isEmpty ? null : Loan.fromMap(r.first);
  }

  /// Loans of one direction: unsettled first (earliest due date first), then settled.
  Future<List<Loan>> loans(String direction) async {
    final rows = await _db.rawQuery('$_loanSelect WHERE l.direction = ?', [direction]);
    final list = rows.map(Loan.fromMap).toList();
    list.sort((a, b) {
      final sa = a.settled ? 1 : 0;
      final sb = b.settled ? 1 : 0;
      if (sa != sb) return sa - sb;
      final c = (a.dueDate ?? '9999').compareTo(b.dueDate ?? '9999');
      if (c != 0) return c;
      return b.at.compareTo(a.at);
    });
    return list;
  }

  Future<int> outstandingTotal(String direction) async {
    final list = await loans(direction);
    return list.fold<int>(0, (sum, l) => sum + (l.outstanding > 0 ? l.outstanding : 0));
  }

  Future<List<Repayment>> repayments(int loanId) async {
    final rows = await _db.query('repayments',
        where: 'loan_id = ?', whereArgs: [loanId], orderBy: 'at DESC, id DESC');
    return rows.map(Repayment.fromMap).toList();
  }

  /// Records a repayment. Never creates income/expense entries.
  Future<void> addRepayment(int loanId, int amount, DateTime at, String note) async {
    if (amount <= 0) throw AppException('The amount must be greater than zero.');
    await _db.transaction((txn) async {
      final r = await txn.rawQuery(
          'SELECT amount, (SELECT COALESCE(SUM(amount), 0) FROM repayments WHERE loan_id = ?) AS repaid '
          'FROM loans WHERE id = ?',
          [loanId, loanId]);
      if (r.isEmpty) throw AppException('This loan no longer exists.');
      final out = (r.first['amount'] as int) - (r.first['repaid'] as int);
      if (amount > out) {
        throw AppException(
            'The repayment is more than the outstanding balance (${formatMoney(out)}).');
      }
      await txn.insert('repayments',
          {'loan_id': loanId, 'amount': amount, 'at': isoLocal(at), 'note': note});
    });
    _changed();
  }

  Future<void> deleteRepayment(int id) async {
    await _db.delete('repayments', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  // ---------------------------------------------------------------- reminders

  Future<int> insertReminder(Reminder r) async {
    final id = await _db.insert('reminders', r.toMap());
    _changed();
    return id;
  }

  Future<void> updateReminder(Reminder r) async {
    await _db.update('reminders', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
    _changed();
  }

  Future<void> deleteReminder(int id) async {
    await _db.delete('reminders', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<List<Reminder>> reminders() async {
    final rows = await _db.query('reminders', orderBy: 'active DESC, at ASC');
    return rows.map(Reminder.fromMap).toList();
  }

  /// Upcoming items from reminders, task reminders and loan due dates.
  /// [forNotifications] expands repeating reminders into several occurrences.
  Future<List<AgendaItem>> agenda(DateTime now, {bool forNotifications = false}) async {
    final out = <AgendaItem>[];

    final trows = await _db.query('tasks',
        where: 'done = 0 AND remind = 1 AND due_time IS NOT NULL');
    for (final t in trows.map(Task.fromMap)) {
      final at = t.dueAt!;
      if (!at.isBefore(now)) {
        out.add(AgendaItem(at, 'Task: ${t.title}',
            t.notes.isEmpty ? 'This task is due now.' : t.notes, 'task'));
      }
    }

    for (final r in await reminders()) {
      if (!r.active) continue;
      final max = !forNotifications
          ? 1
          : (r.repeat == 'daily' ? 30 : (r.repeat == 'weekly' ? 12 : (r.repeat == 'monthly' ? 6 : 1)));
      for (final when in upcomingOccurrences(r.when, r.repeat, now, max)) {
        out.add(AgendaItem(when, r.title, r.notes.isEmpty ? 'Reminder' : r.notes,
            r.kind == 'bill' ? 'bill' : 'reminder'));
      }
    }

    for (final dir in const ['borrowed', 'lent']) {
      for (final l in await loans(dir)) {
        if (l.settled || l.dueDate == null) continue;
        final when = combine(l.dueDate!, '09:00');
        if (forNotifications ? !when.isAfter(now) : l.dueDate!.compareTo(dateKey(now)) < 0) {
          continue;
        }
        final text = dir == 'lent'
            ? '${l.person} should repay you ${formatMoney(l.outstanding)}.'
            : 'You should repay ${l.person} ${formatMoney(l.outstanding)}.';
        out.add(AgendaItem(when, 'Loan repayment due', text, 'loan'));
      }
    }

    out.sort((a, b) => a.when.compareTo(b.when));
    return out;
  }

  // ---------------------------------------------------------------- backup

  Future<Map<String, Object?>> exportAll() async {
    final data = <String, Object?>{};
    for (final t in tableColumns.keys) {
      data[t] = await _db.query(t);
    }
    return {
      'app': backupAppId,
      'version': backupVersion,
      'exportedAt': isoLocal(DateTime.now()),
      'data': data,
    };
  }

  /// Replaces ALL data with the backup, in one transaction (all-or-nothing).
  Future<void> importAll(Map<String, Object?> json) async {
    final err = validateBackup(json);
    if (err != null) throw AppException(err);
    final data = json['data'] as Map;
    await _db.transaction((txn) async {
      for (final t in const [
        'repayments', 'loans', 'tasks', 'transactions', 'budgets', 'reminders', 'settings'
      ]) {
        await txn.delete(t);
      }
      for (final t in tableColumns.keys) {
        for (final row in data[t] as List) {
          final r = row as Map;
          final m = <String, Object?>{};
          for (final c in tableColumns[t]!) {
            if (r.containsKey(c)) m[c] = r[c];
          }
          await txn.insert(t, m);
        }
      }
    });
    _changed();
  }
}
