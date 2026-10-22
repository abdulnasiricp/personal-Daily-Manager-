/// Backup file format + validation (pure Dart, no database access).
const backupAppId = 'PersonalDailyManager';
const backupVersion = 1;

const tableColumns = <String, List<String>>{
  'tasks': ['id', 'title', 'notes', 'due_date', 'due_time', 'priority', 'done', 'done_at', 'remind'],
  'transactions': ['id', 'type', 'amount', 'category', 'description', 'at'],
  'budgets': ['month', 'amount'],
  'loans': ['id', 'direction', 'person', 'phone', 'amount', 'at', 'due_date', 'note'],
  'repayments': ['id', 'loan_id', 'amount', 'at', 'note'],
  'reminders': ['id', 'title', 'notes', 'at', 'repeat_mode', 'kind', 'active'],
  'settings': ['name', 'value'],
};

const _required = <String, List<String>>{
  'tasks': ['id', 'title', 'due_date', 'priority', 'done', 'remind'],
  'transactions': ['id', 'type', 'amount', 'category', 'at'],
  'budgets': ['month', 'amount'],
  'loans': ['id', 'direction', 'person', 'amount', 'at'],
  'repayments': ['id', 'loan_id', 'amount', 'at'],
  'reminders': ['id', 'title', 'at', 'repeat_mode', 'kind', 'active'],
  'settings': ['name', 'value'],
};

const _intCols = {'id', 'priority', 'done', 'remind', 'amount', 'loan_id', 'active'};
final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _timeRe = RegExp(r'^\d{2}:\d{2}$');
final _monthRe = RegExp(r'^\d{4}-\d{2}$');

/// Returns null when the backup is valid, otherwise a readable error.
String? validateBackup(Object? json) {
  if (json is! Map) return 'This file is not a valid backup (wrong structure).';
  if (json['app'] != backupAppId) {
    return 'This file was not created by Personal Daily Manager.';
  }
  final v = json['version'];
  if (v is! int) return 'The backup version is missing.';
  if (v > backupVersion) return 'This backup was made by a newer version of the app.';
  final data = json['data'];
  if (data is! Map) return 'The backup data section is missing.';

  for (final t in tableColumns.keys) {
    final rows = data[t];
    if (rows is! List) return 'The backup is missing the "$t" section.';
    final ids = <Object?>{};
    for (final row in rows) {
      if (row is! Map) return 'A corrupted entry was found in "$t".';
      for (final c in _required[t]!) {
        if (row[c] == null) return 'An entry in "$t" is missing "$c".';
      }
      for (final c in tableColumns[t]!) {
        final x = row[c];
        if (x == null) continue;
        if (_intCols.contains(c)) {
          if (x is! int) return 'Invalid number in "$t.$c".';
        } else if (x is! String) {
          return 'Invalid text in "$t.$c".';
        }
      }
      final key = t == 'budgets'
          ? row['month']
          : (t == 'settings' ? row['name'] : row['id']);
      if (!ids.add(key)) return 'Duplicate entry found in "$t".';

      switch (t) {
        case 'tasks':
          if (!_dateRe.hasMatch(row['due_date'] as String)) return 'Invalid task date.';
          final tm = row['due_time'];
          if (tm != null && !_timeRe.hasMatch(tm as String)) return 'Invalid task time.';
          if (!const [0, 1, 2].contains(row['priority'])) return 'Invalid task priority.';
          if (!const [0, 1].contains(row['done']) || !const [0, 1].contains(row['remind'])) {
            return 'Invalid task flag.';
          }
          break;
        case 'transactions':
          if (!const ['income', 'expense'].contains(row['type'])) {
            return 'Invalid transaction type.';
          }
          if ((row['amount'] as int) <= 0) return 'Invalid transaction amount.';
          if (DateTime.tryParse(row['at'] as String) == null) {
            return 'Invalid transaction date.';
          }
          break;
        case 'budgets':
          if (!_monthRe.hasMatch(row['month'] as String)) return 'Invalid budget month.';
          if ((row['amount'] as int) < 0) return 'Invalid budget amount.';
          break;
        case 'loans':
          if (!const ['borrowed', 'lent'].contains(row['direction'])) {
            return 'Invalid loan type.';
          }
          if ((row['amount'] as int) <= 0) return 'Invalid loan amount.';
          if (DateTime.tryParse(row['at'] as String) == null) return 'Invalid loan date.';
          final d = row['due_date'];
          if (d != null && !_dateRe.hasMatch(d as String)) return 'Invalid loan due date.';
          break;
        case 'repayments':
          if ((row['amount'] as int) <= 0) return 'Invalid repayment amount.';
          if (DateTime.tryParse(row['at'] as String) == null) {
            return 'Invalid repayment date.';
          }
          break;
        case 'reminders':
          if (!const ['none', 'daily', 'weekly', 'monthly'].contains(row['repeat_mode'])) {
            return 'Invalid reminder repeat.';
          }
          if (DateTime.tryParse(row['at'] as String) == null) {
            return 'Invalid reminder date.';
          }
          if (!const [0, 1].contains(row['active'])) return 'Invalid reminder flag.';
          break;
      }
    }
  }

  // Referential integrity: repayments must belong to a loan and never exceed it.
  final loanAmounts = <Object?, int>{};
  for (final l in data['loans'] as List) {
    final m = l as Map;
    loanAmounts[m['id']] = m['amount'] as int;
  }
  final repaid = <Object?, int>{};
  for (final r in data['repayments'] as List) {
    final m = r as Map;
    if (!loanAmounts.containsKey(m['loan_id'])) {
      return 'A repayment refers to a loan that is not in the backup.';
    }
    repaid[m['loan_id']] = (repaid[m['loan_id']] ?? 0) + (m['amount'] as int);
  }
  for (final e in repaid.entries) {
    if (e.value > loanAmounts[e.key]!) return 'Repayments exceed a loan amount.';
  }
  return null;
}

/// Short human summary for the restore confirmation dialog.
String backupSummary(Map json) {
  final d = json['data'] as Map;
  int n(String t) => (d[t] as List).length;
  return '${n('tasks')} tasks, ${n('transactions')} transactions, '
      '${n('loans')} loans, ${n('repayments')} repayments, ${n('reminders')} reminders';
}
