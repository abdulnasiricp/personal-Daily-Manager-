import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../backup.dart';
import '../calc.dart';
import '../db.dart';
import '../notifications.dart';
import 'common.dart';

class MorePage extends StatefulWidget {
  const MorePage({super.key});
  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> with Refreshable<MorePage> {
  bool _dark = false;

  @override
  Future<void> reload() async {
    final v = await AppDb.instance.getSetting('dark');
    if (mounted) setState(() => _dark = v == '1');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text('Reminders'),
          subtitle: const Text('Bills, appointments and repeating reminders'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RemindersPage())),
        ),
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('Backup & Restore'),
          subtitle: const Text('Save or restore all your data'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupPage())),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.dark_mode_outlined),
          title: const Text('Dark mode'),
          value: _dark,
          onChanged: (v) => AppDb.instance.setSetting('dark', v ? '1' : '0'),
        ),
        const Divider(),
        const ListTile(
          leading: Icon(Icons.payments_outlined),
          title: Text('Currency'),
          subtitle: Text('Pakistani Rupee (PKR)'),
        ),
        const ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text('Privacy'),
          subtitle: Text('All data stays on this phone. The app works fully offline and has no accounts.'),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ reminders

class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key});
  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> with Refreshable<RemindersPage> {
  List<Reminder> _items = [];
  bool _loaded = false;
  bool _notifOk = true;
  bool _exactOk = true;

  @override
  Future<void> reload() async {
    final r = await AppDb.instance.reminders();
    final n = await Notifier.notificationsEnabled();
    final e = await Notifier.canScheduleExact();
    if (!mounted) return;
    setState(() {
      _items = r;
      _notifOk = n;
      _exactOk = e;
      _loaded = true;
    });
  }

  String _repeatText(String r) =>
      const {'none': 'Once', 'daily': 'Every day', 'weekly': 'Every week', 'monthly': 'Every month'}[r] ?? r;

  Future<void> _delete(Reminder r) async {
    if (await confirm(context, 'Delete reminder?', '"${r.title}" will be permanently deleted.')) {
      await AppDb.instance.deleteReminder(r.id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showForm(context, const ReminderForm()),
        icon: const Icon(Icons.add),
        label: const Text('Add reminder'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
              if (!_notifOk)
                Card(
                  color: cs.errorContainer,
                  child: ListTile(
                    leading: Icon(Icons.notifications_off, color: cs.onErrorContainer),
                    title: Text('Notifications are off', style: TextStyle(color: cs.onErrorContainer)),
                    subtitle: Text('Allow notifications so reminders can alert you.',
                        style: TextStyle(color: cs.onErrorContainer)),
                    trailing: FilledButton(
                      onPressed: () async {
                        final ok = await Notifier.ensurePermission();
                        if (!ok && mounted) {
                          toast(context, 'Please enable notifications for this app in Android Settings.');
                        }
                        reload();
                      },
                      child: const Text('Allow'),
                    ),
                  ),
                ),
              if (_notifOk && !_exactOk)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.alarm),
                    title: const Text('Exact timing is not allowed'),
                    subtitle: const Text('Reminders may arrive a few minutes late. Allow "Alarms & reminders" for exact timing.'),
                    trailing: TextButton(
                      onPressed: () async {
                        await Notifier.requestExactAlarms();
                      },
                      child: const Text('Allow'),
                    ),
                  ),
                ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.send_outlined),
                  title: const Text('Send a test notification'),
                  onTap: () async {
                    final ok = await Notifier.ensurePermission();
                    if (ok) {
                      await Notifier.showTest();
                    } else if (mounted) {
                      toast(context, 'Notifications are not allowed.');
                    }
                    reload();
                  },
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Task reminders are set in each task. Loan repayment reminders are sent at 9:00 AM on the expected repayment date. Open the app now and then so repeating reminders stay scheduled.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SectionTitle('Your reminders'),
              if (_items.isEmpty)
                const EmptyState(icon: Icons.notifications_none, message: 'No reminders yet.\nTap "Add reminder" to create one.')
              else
                ..._items.map((r) {
                  final next = r.active ? upcomingOccurrences(r.when, r.repeat, now, 1) : <DateTime>[];
                  final sub = !r.active
                      ? 'Paused'
                      : next.isEmpty
                          ? 'Finished (${fmtDateTime(r.when)})'
                          : 'Next: ${fmtDateTime(next.first)}';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => showForm(context, ReminderForm(reminder: r)),
                      leading: Icon(r.kind == 'bill' ? Icons.receipt_long : Icons.notifications_active_outlined),
                      title: Text(r.title),
                      subtitle: Text('$sub\n${_repeatText(r.repeat)}${r.kind == 'bill' ? '  -  Bill' : ''}'),
                      isThreeLine: true,
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Switch(
                          value: r.active,
                          onChanged: (v) => AppDb.instance.updateReminder(Reminder(
                              id: r.id,
                              title: r.title,
                              notes: r.notes,
                              at: r.at,
                              repeat: r.repeat,
                              kind: r.kind,
                              active: v)),
                        ),
                        IconButton(
                            icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: () => _delete(r)),
                      ]),
                    ),
                  );
                }),
            ]),
    );
  }
}

class ReminderForm extends StatefulWidget {
  final Reminder? reminder;
  const ReminderForm({super.key, this.reminder});
  @override
  State<ReminderForm> createState() => _ReminderFormState();
}

class _ReminderFormState extends State<ReminderForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _title = TextEditingController(text: widget.reminder?.title ?? '');
  late final TextEditingController _notes = TextEditingController(text: widget.reminder?.notes ?? '');
  late DateTime _when = widget.reminder?.when ?? DateTime.now().add(const Duration(hours: 1));
  late String _repeat = widget.reminder?.repeat ?? 'none';
  late String _kind = widget.reminder?.kind ?? 'general';
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    if (_repeat == 'none' && _when.isBefore(DateTime.now()) && widget.reminder == null) {
      setState(() => _error = 'That time has already passed. Pick a future time or a repeat option.');
      return;
    }
    final old = widget.reminder;
    final r = Reminder(
      id: old?.id,
      title: _title.text.trim(),
      notes: _notes.text.trim(),
      at: isoLocal(DateTime(_when.year, _when.month, _when.day, _when.hour, _when.minute)),
      repeat: _repeat,
      kind: _kind,
      active: old?.active ?? true,
    );
    try {
      if (r.id == null) {
        await AppDb.instance.insertReminder(r);
      } else {
        await AppDb.instance.updateReminder(r);
      }
      await Notifier.ensurePermission();
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
        Text(widget.reminder == null ? 'New reminder' : 'Edit reminder',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'general', label: Text('General'), icon: Icon(Icons.notifications_active_outlined)),
            ButtonSegment(value: 'bill', label: Text('Bill'), icon: Icon(Icons.receipt_long)),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Title'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a title' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notes,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Notes (optional)'),
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
        DropdownButtonFormField<String>(
          value: _repeat,
          decoration: const InputDecoration(labelText: 'Repeat'),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('Does not repeat')),
            DropdownMenuItem(value: 'daily', child: Text('Every day')),
            DropdownMenuItem(value: 'weekly', child: Text('Every week')),
            DropdownMenuItem(value: 'monthly', child: Text('Every month')),
          ],
          onChanged: (v) => setState(() => _repeat = v ?? 'none'),
        ),
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

// ------------------------------------------------------------------ backup

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final data = await AppDb.instance.exportAll();
      final dir = await getTemporaryDirectory();
      final name = 'PersonalDailyManager_backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json';
      final file = File(p.join(dir.path, name));
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/json')],
          subject: 'Personal Daily Manager backup');
      if (mounted) {
        toast(context, 'Backup file created. Choose "Save to Drive", "Files" or send it to yourself to keep it safe.');
      }
    } catch (e) {
      if (mounted) toast(context, 'Backup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.any);
      if (picked == null || picked.files.single.path == null) return;
      final text = await File(picked.files.single.path!).readAsString();

      Object? json;
      try {
        json = jsonDecode(text);
      } catch (_) {
        if (mounted) toast(context, 'This file is not a valid backup (it could not be read).');
        return;
      }
      final err = validateBackup(json);
      if (err != null) {
        if (mounted) toast(context, err);
        return;
      }
      final map = Map<String, Object?>.from(json as Map);
      if (!mounted) return;
      final ok = await confirm(
        context,
        'Replace all current data?',
        'This backup contains ${backupSummary(map)}.\n\nRestoring will DELETE everything currently in the app and replace it with the backup. '
            'A safety copy of your current data will be saved first.',
        yes: 'Replace data',
      );
      if (!ok) return;

      // Safety copy of the current data before anything is overwritten.
      final docs = await getApplicationDocumentsDirectory();
      final safety = File(p.join(docs.path, 'before_last_restore.json'));
      await safety.writeAsString(jsonEncode(await AppDb.instance.exportAll()));

      await AppDb.instance.importAll(map);
      if (mounted) toast(context, 'Backup restored successfully.');
    } on AppException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, 'Restore failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        InfoCard(
          title: 'Export backup',
          icon: Icons.upload_file,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
                'Creates one file with all your tasks, transactions, loans, repayments, reminders and settings. '
                'Then choose where to keep it: Google Drive, Files, WhatsApp, email, etc.'),
            const SizedBox(height: 12),
            FilledButton.icon(
                onPressed: _busy ? null : _export, icon: const Icon(Icons.ios_share), label: const Text('Export & save backup')),
          ]),
        ),
        InfoCard(
          title: 'Restore backup',
          icon: Icons.download,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
                'Pick a backup file you exported earlier. The file is checked first, and you will be asked to confirm before your current data is replaced.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: _busy ? null : _restore, icon: const Icon(Icons.folder_open), label: const Text('Choose backup file')),
          ]),
        ),
        if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      ]),
    );
  }
}
