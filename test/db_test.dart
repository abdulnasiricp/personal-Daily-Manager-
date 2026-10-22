import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_daily_manager/calc.dart';
import 'package:personal_daily_manager/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDb db;
  setUp(() async {
    db = AppDb();
    await db.open(path: inMemoryDatabasePath);
  });
  tearDown(() async => db.close());

  Loan loan(String dir, int amount, {String? due}) => Loan(
      direction: dir, person: 'Ali', amount: amount, at: '2026-10-01T10:00:00', dueDate: due);

  test('loan principal and repayments never count as income or expense', () async {
    final id = await db.insertLoan(loan('lent', 500000));
    await db.addRepayment(id, 200000, DateTime(2026, 10, 5, 12), '');
    final t = await db.totals(monthRange(DateTime(2026, 10, 15)));
    expect(t.income, 0);
    expect(t.expense, 0);
    expect((await db.loan(id))!.outstanding, 300000);
  });

  test('partial then full repayment settles the loan', () async {
    final id = await db.insertLoan(loan('borrowed', 100000));
    await db.addRepayment(id, 30000, DateTime(2026, 10, 2), '');
    expect((await db.loan(id))!.settled, isFalse);
    await db.addRepayment(id, 70000, DateTime(2026, 10, 3), '');
    expect((await db.loan(id))!.settled, isTrue);
    expect((await db.repayments(id)).length, 2);
    expect(await db.outstandingTotal('borrowed'), 0);
  });

  test('over-repayment and zero repayment are rejected', () async {
    final id = await db.insertLoan(loan('lent', 1000));
    expect(() => db.addRepayment(id, 1001, DateTime(2026, 10, 2), ''), throwsA(isA<AppException>()));
    expect(() => db.addRepayment(id, 0, DateTime(2026, 10, 2), ''), throwsA(isA<AppException>()));
    expect((await db.loan(id))!.repaid, 0);
  });

  test('loan amount cannot be edited below what was repaid', () async {
    final id = await db.insertLoan(loan('lent', 1000));
    await db.addRepayment(id, 600, DateTime(2026, 10, 2), '');
    final l = (await db.loan(id))!;
    expect(
        () => db.updateLoan(Loan(id: id, direction: l.direction, person: l.person, amount: 500, at: l.at)),
        throwsA(isA<AppException>()));
  });

  test('outstanding totals are kept separate per direction', () async {
    await db.insertLoan(loan('lent', 300000));
    await db.insertLoan(loan('borrowed', 100000));
    expect(await db.outstandingTotal('lent'), 300000);
    expect(await db.outstandingTotal('borrowed'), 100000);
  });

  test('deleting a loan removes its repayments', () async {
    final id = await db.insertLoan(loan('lent', 1000));
    await db.addRepayment(id, 100, DateTime(2026, 10, 2), '');
    await db.deleteLoan(id);
    expect(await db.loan(id), isNull);
    expect(await db.repayments(id), isEmpty);
  });

  test('month summary: income, expense, budget remaining', () async {
    await db.setBudget('2026-10', 100000);
    await db.insertTxn(const Txn(type: 'income', amount: 500000, category: 'Salary', at: '2026-10-01T09:00:00'));
    await db.insertTxn(const Txn(type: 'expense', amount: 30000, category: 'Food', at: '2026-10-02T13:00:00'));
    await db.insertTxn(const Txn(type: 'expense', amount: 5050, category: 'Transport', at: '2026-10-03T08:00:00'));
    final s = await db.monthSummary(DateTime(2026, 10, 20));
    expect(s.income, 500000);
    expect(s.expense, 35050);
    expect(s.remainingBudget, 64950);
    expect(s.net, 464950);
  });

  test('month boundaries are exact', () async {
    await db.insertTxn(const Txn(type: 'expense', amount: 100, category: 'Food', at: '2026-10-31T23:59:59'));
    await db.insertTxn(const Txn(type: 'expense', amount: 200, category: 'Food', at: '2026-11-01T00:00:00'));
    expect((await db.totals(monthRange(DateTime(2026, 10, 10)))).expense, 100);
    expect((await db.totals(monthRange(DateTime(2026, 11, 10)))).expense, 200);
  });

  test('daily and weekly totals', () async {
    await db.insertTxn(const Txn(type: 'expense', amount: 100, category: 'Food', at: '2026-10-21T10:00:00')); // Wed
    await db.insertTxn(const Txn(type: 'expense', amount: 200, category: 'Food', at: '2026-10-19T10:00:00')); // Mon
    await db.insertTxn(const Txn(type: 'expense', amount: 400, category: 'Food', at: '2026-10-26T10:00:00')); // next Mon
    final day = DateTime(2026, 10, 21);
    expect((await db.totals(dayRange(day))).expense, 100);
    expect((await db.totals(weekRange(day))).expense, 300);
  });

  test('budget carries forward until changed', () async {
    await db.setBudget('2026-09', 80000);
    expect(await db.budgetFor('2026-08'), 0);
    expect(await db.budgetFor('2026-09'), 80000);
    expect(await db.budgetFor('2026-11'), 80000);
    await db.setBudget('2026-10', 90000);
    expect(await db.budgetFor('2026-11'), 90000);
    expect(await db.budgetFor('2026-09'), 80000);
  });

  test('task progress and completion', () async {
    final day = DateTime(2026, 10, 21);
    final a = await db.insertTask(Task(title: 'A', dueDate: dateKey(day)));
    await db.insertTask(Task(title: 'B', dueDate: dateKey(day)));
    await db.setTaskDone(a, true);
    final prog = await db.taskProgress(day);
    expect(prog.done, 1);
    expect(prog.total, 2);
    expect((await db.tasks(done: true)).single.title, 'A');
    expect((await db.tasks(done: false)).single.title, 'B');
    await db.setTaskDone(a, false);
    expect((await db.tasks(done: true)), isEmpty);
  });

  test('agenda expands repeating reminders and includes loan due dates', () async {
    await db.insertReminder(Reminder(title: 'Rent', at: '2026-10-01T09:00:00', repeat: 'monthly', kind: 'bill'));
    await db.insertReminder(Reminder(title: 'Paused', at: '2026-10-22T09:00:00', active: false));
    await db.insertLoan(loan('lent', 1000, due: '2026-10-25'));
    final now = DateTime(2026, 10, 21, 8);
    final a = await db.agenda(now, forNotifications: true);
    expect(a.where((i) => i.title == 'Rent').length, 6);
    expect(a.any((i) => i.title == 'Paused'), isFalse);
    expect(a.any((i) => i.kind == 'loan' && i.when == DateTime(2026, 10, 25, 9)), isTrue);
    expect(a.first.when.isBefore(a.last.when), isTrue);
    final dash = await db.agenda(now);
    expect(dash.where((i) => i.title == 'Rent').length, 1);
  });

  test('backup export then restore reproduces all data', () async {
    final id = await db.insertLoan(loan('lent', 1000, due: '2026-12-01'));
    await db.addRepayment(id, 250, DateTime(2026, 10, 2), 'part');
    await db.insertTxn(const Txn(type: 'expense', amount: 700, category: 'Food', at: '2026-10-02T13:00:00'));
    await db.insertTask(const Task(title: 'T', dueDate: '2026-10-21', dueTime: '09:30', remind: true));
    await db.insertReminder(Reminder(title: 'R', at: '2026-10-22T09:00:00', repeat: 'weekly'));
    await db.setBudget('2026-10', 5000);
    await db.setSetting('dark', '1');

    final exported = jsonDecode(jsonEncode(await db.exportAll())) as Map<String, Object?>;

    // Change the data, then restore.
    await db.deleteLoan(id);
    await db.insertTxn(const Txn(type: 'income', amount: 9999, category: 'Gift', at: '2026-10-03T10:00:00'));
    await db.importAll(exported);

    final again = jsonDecode(jsonEncode(await db.exportAll())) as Map<String, Object?>;
    expect(again['data'], exported['data']);
    expect((await db.loan(id))!.outstanding, 750);
  });

  test('invalid backup is rejected and leaves data untouched', () async {
    await db.insertTxn(const Txn(type: 'expense', amount: 700, category: 'Food', at: '2026-10-02T13:00:00'));
    expect(() => db.importAll({'app': 'x'}), throwsA(isA<AppException>()));
    expect((await db.totals(monthRange(DateTime(2026, 10, 1)))).expense, 700);
  });

  test('data persists after closing and reopening the database file', () async {
    final dir = await Directory.systemTemp.createTemp('pdm_test');
    final path = p.join(dir.path, 'test.db');
    final a = AppDb();
    await a.open(path: path);
    await a.insertTxn(const Txn(type: 'expense', amount: 1234, category: 'Food', at: '2026-10-02T13:00:00'));
    await a.close();
    final b = AppDb();
    await b.open(path: path);
    expect((await b.totals(monthRange(DateTime(2026, 10, 1)))).expense, 1234);
    await b.close();
    await dir.delete(recursive: true);
  });
}
