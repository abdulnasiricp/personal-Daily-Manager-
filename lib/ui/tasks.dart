import 'package:flutter/material.dart';

import '../calc.dart';
import '../db.dart';
import '../notifications.dart';
import 'common.dart';

const _priorityNames = ['Low', 'Medium', 'High'];
const _priorityColors = [Color(0xFF607D8B), Color(0xFFEF6C00), Color(0xFFC62828)];

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> with Refreshable<TasksPage> {
  List<Task> _pending = [];
  List<Task> _completed = [];
  bool _loaded = false;

  @override
  Future<void> reload() async {
    final p = await AppDb.instance.tasks(done: false);
    final c = await AppDb.instance.tasks(done: true);
    if (!mounted) return;
    setState(() {
      _pending = p;
      _completed = c;
      _loaded = true;
    });
  }

  Future<void> _delete(Task t) async {
    if (await confirm(context, 'Delete task?', '"${t.title}" will be permanently deleted.')) {
      await AppDb.instance.deleteTask(t.id!);
      if (mounted) toast(context, 'Task deleted');
    }
  }

  Widget _tile(Task t) {
    final cs = Theme.of(context).colorScheme;
    final overdue = !t.done && t.dueDate.compareTo(dateKey(DateTime.now())) < 0;
    final when = DateTime.parse(t.dueDate);
    final dateText = t.dueTime == null
        ? fmtDate(when)
        : '${fmtDate(when)}, ${fmtTime(t.dueAt!)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => showForm(context, TaskForm(task: t)),
        leading: Checkbox(
          value: t.done,
          onChanged: (v) => AppDb.instance.setTaskDone(t.id!, v ?? false),
        ),
        title: Text(t.title,
            style: TextStyle(
                decoration: t.done ? TextDecoration.lineThrough : null,
                color: t.done ? cs.outline : null)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dateText, style: TextStyle(color: overdue ? cs.error : null)),
          if (t.notes.isNotEmpty) Text(t.notes, maxLines: 2, overflow: TextOverflow.ellipsis),
          Row(children: [
            Icon(Icons.flag, size: 14, color: _priorityColors[t.priority]),
            const SizedBox(width: 4),
            Text(_priorityNames[t.priority], style: const TextStyle(fontSize: 12)),
            if (t.remind) ...[
              const SizedBox(width: 10),
              const Icon(Icons.notifications_active, size: 14),
            ],
            if (overdue) ...[
              const SizedBox(width: 10),
              Text('OVERDUE', style: TextStyle(fontSize: 12, color: cs.error, fontWeight: FontWeight.w700)),
            ],
          ]),
        ]),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete',
          onPressed: () => _delete(t),
        ),
      ),
    );
  }

  Widget _list(List<Task> items, String empty, IconData icon) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) return Center(child: EmptyState(icon: icon, message: empty));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: items.map(_tile).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Daily Tasks'),
          bottom: TabBar(tabs: [
            Tab(text: 'Pending (${_pending.length})'),
            Tab(text: 'Completed (${_completed.length})'),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showForm(context, const TaskForm()),
          icon: const Icon(Icons.add),
          label: const Text('Add task'),
        ),
        body: TabBarView(children: [
          _list(_pending, 'No pending tasks.\nTap "Add task" to create one.', Icons.task_alt),
          _list(_completed, 'No completed tasks yet.', Icons.check_circle_outline),
        ]),
      ),
    );
  }
}

class TaskForm extends StatefulWidget {
  final Task? task;
  const TaskForm({super.key, this.task});
  @override
  State<TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<TaskForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _title = TextEditingController(text: widget.task?.title ?? '');
  late final TextEditingController _notes = TextEditingController(text: widget.task?.notes ?? '');
  late DateTime _date = widget.task == null ? dateOnly(DateTime.now()) : DateTime.parse(widget.task!.dueDate);
  TimeOfDay? _time;
  late int _priority = widget.task?.priority ?? 1;
  late bool _remind = widget.task?.remind ?? false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final t = widget.task?.dueTime;
    if (t != null) {
      final p = t.split(':');
      _time = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    if (_remind && _time == null) {
      setState(() => _error = 'Pick a time to turn on the reminder.');
      return;
    }
    final old = widget.task;
    final t = Task(
      id: old?.id,
      title: _title.text.trim(),
      notes: _notes.text.trim(),
      dueDate: dateKey(_date),
      dueTime: _time == null ? null : timeKey(_time!.hour, _time!.minute),
      priority: _priority,
      done: old?.done ?? false,
      doneAt: old?.doneAt,
      remind: _remind,
    );
    try {
      if (t.id == null) {
        await AppDb.instance.insertTask(t);
      } else {
        await AppDb.instance.updateTask(t);
      }
      if (_remind) await Notifier.ensurePermission();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = 'Could not save the task: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.task == null ? 'New task' : 'Edit task', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextFormField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Title'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a title' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notes,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Notes (optional)'),
        ),
        const SizedBox(height: 12),
        PickTile(
          icon: Icons.calendar_today,
          label: 'Date',
          value: fmtDate(_date),
          onTap: () async {
            final d = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100));
            if (d != null) setState(() => _date = d);
          },
        ),
        const SizedBox(height: 12),
        PickTile(
          icon: Icons.access_time,
          label: 'Time (optional)',
          value: _time == null ? 'No time' : _time!.format(context),
          onTap: () async {
            final t = await showTimePicker(context: context, initialTime: _time ?? TimeOfDay.now());
            if (t != null) setState(() => _time = t);
          },
          onClear: _time == null ? null : () => setState(() { _time = null; _remind = false; }),
        ),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Low')),
            ButtonSegment(value: 1, label: Text('Medium')),
            ButtonSegment(value: 2, label: Text('High')),
          ],
          selected: {_priority},
          onSelectionChanged: (s) => setState(() => _priority = s.first),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Remind me at the set time'),
          value: _remind,
          onChanged: (v) => setState(() { _remind = v; _error = null; }),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ]),
    );
  }
}
