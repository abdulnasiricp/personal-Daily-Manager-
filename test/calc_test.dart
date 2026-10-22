import 'package:flutter_test/flutter_test.dart';
import 'package:personal_daily_manager/backup.dart';
import 'package:personal_daily_manager/calc.dart';

void main() {
  group('money', () {
    test('parses valid input to paisa', () {
      expect(parseMoney('1500'), 150000);
      expect(parseMoney('1,250.50'), 125050);
      expect(parseMoney('0.5'), 50);
      expect(parseMoney('Rs. 20'), 2000);
    });
    test('rejects invalid input', () {
      expect(parseMoney(''), isNull);
      expect(parseMoney('abc'), isNull);
      expect(parseMoney('-5'), isNull);
      expect(parseMoney('1.234'), isNull);
      expect(parseMoney('.5'), isNull);
    });
    test('formats', () {
      expect(formatMoney(150000), 'PKR 1,500');
      expect(formatMoney(125050), 'PKR 1,250.50');
      expect(formatMoney(-5000), '-PKR 50');
      expect(moneyInput(125050), '1250.50');
      expect(moneyInput(100), '1');
    });
    test('0.1 + 0.2 style rounding cannot happen', () {
      expect(parseMoney('0.1')! + parseMoney('0.2')!, parseMoney('0.3'));
    });
  });

  group('budget', () {
    test('remaining budget and net are separate, correct values', () {
      const s = MonthSummary(500000, 300000, 400000);
      expect(s.remainingBudget, 100000);
      expect(s.net, 200000);
      expect(const MonthSummary(0, 450000, 400000).remainingBudget, -50000);
    });
  });

  group('ranges', () {
    test('week starts Monday', () {
      final r = weekRange(DateTime(2026, 10, 21)); // Wednesday
      expect(r.start, DateTime(2026, 10, 19));
      expect(r.end, DateTime(2026, 10, 26));
    });
    test('month range handles December', () {
      final r = monthRange(DateTime(2026, 12, 15));
      expect(r.start, DateTime(2026, 12, 1));
      expect(r.end, DateTime(2027, 1, 1));
    });
  });

  group('loans', () {
    test('overdue only when unpaid and past due date', () {
      final now = DateTime(2026, 10, 21, 15);
      expect(isOverdue('2026-10-20', 100, now), isTrue);
      expect(isOverdue('2026-10-21', 100, now), isFalse);
      expect(isOverdue('2026-10-20', 0, now), isFalse);
      expect(isOverdue(null, 100, now), isFalse);
    });
  });

  group('reminder recurrence', () {
    test('one-off in the past gives nothing', () {
      expect(upcomingOccurrences(DateTime(2026, 1, 1, 9), 'none', DateTime(2026, 2, 1), 3), isEmpty);
    });
    test('daily', () {
      final r = upcomingOccurrences(DateTime(2026, 10, 1, 9), 'daily', DateTime(2026, 10, 21, 10), 2);
      expect(r, [DateTime(2026, 10, 22, 9), DateTime(2026, 10, 23, 9)]);
    });
    test('weekly keeps the weekday', () {
      final r = upcomingOccurrences(DateTime(2026, 10, 5, 8), 'weekly', DateTime(2026, 10, 21), 2);
      expect(r, [DateTime(2026, 10, 26, 8), DateTime(2026, 11, 2, 8)]);
    });
    test('monthly on the 31st clamps to month end and recovers', () {
      final r = upcomingOccurrences(DateTime(2026, 1, 31, 9), 'monthly', DateTime(2026, 2, 1), 3);
      expect(r, [DateTime(2026, 2, 28, 9), DateTime(2026, 3, 31, 9), DateTime(2026, 4, 30, 9)]);
    });
    test('reminder exactly now is still upcoming', () {
      final t = DateTime(2026, 10, 21, 9);
      expect(upcomingOccurrences(t, 'daily', t, 1), [t]);
    });
  });

  group('backup validation', () {
    Map<String, Object?> valid() => {
          'app': backupAppId,
          'version': 1,
          'data': {
            'tasks': [],
            'transactions': [],
            'budgets': [],
            'loans': [
              {'id': 1, 'direction': 'lent', 'person': 'A', 'amount': 1000, 'at': '2026-10-01T10:00:00'}
            ],
            'repayments': [
              {'id': 1, 'loan_id': 1, 'amount': 400, 'at': '2026-10-02T10:00:00'}
            ],
            'reminders': [],
            'settings': [],
          },
        };

    test('accepts a valid backup', () => expect(validateBackup(valid()), isNull));
    test('rejects non-map', () => expect(validateBackup([1, 2]), isNotNull));
    test('rejects foreign file', () {
      final b = valid()..['app'] = 'Other';
      expect(validateBackup(b), isNotNull);
    });
    test('rejects newer version', () {
      final b = valid()..['version'] = 99;
      expect(validateBackup(b), isNotNull);
    });
    test('rejects missing section', () {
      final b = valid();
      (b['data'] as Map).remove('loans');
      expect(validateBackup(b), isNotNull);
    });
    test('rejects orphan repayment', () {
      final b = valid();
      ((b['data'] as Map)['repayments'] as List)[0]['loan_id'] = 77;
      expect(validateBackup(b), isNotNull);
    });
    test('rejects repayments above the loan amount', () {
      final b = valid();
      ((b['data'] as Map)['repayments'] as List)[0]['amount'] = 5000;
      expect(validateBackup(b), isNotNull);
    });
    test('rejects bad types', () {
      final b = valid();
      ((b['data'] as Map)['loans'] as List)[0]['amount'] = '1000';
      expect(validateBackup(b), isNotNull);
    });
  });
}
