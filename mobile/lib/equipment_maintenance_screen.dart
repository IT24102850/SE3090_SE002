import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/app_notifications.dart';

class EquipmentMaintenanceScreen extends StatefulWidget {
  const EquipmentMaintenanceScreen({super.key});

  @override
  State<EquipmentMaintenanceScreen> createState() =>
      _EquipmentMaintenanceScreenState();
}

class _EquipmentMaintenanceScreenState
    extends State<EquipmentMaintenanceScreen> {
  final _picker = ImagePicker();
  late List<_MaintenanceTask> _tasks;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('maintenance.tasks.v1');
      final stored = raw == null ? null : jsonDecode(raw) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _tasks = stored == null
            ? _MaintenanceTask.defaults()
            : stored
                .whereType<Map<String, dynamic>>()
                .map(_MaintenanceTask.fromJson)
                .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tasks = _MaintenanceTask.defaults();
        _loading = false;
      });
      showAppNotification(
          'Saved maintenance data was reset because it could not be read.',
          tone: AppNotificationTone.warning);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('maintenance.tasks.v1',
        jsonEncode(_tasks.map((task) => task.toJson()).toList()));
  }

  Future<void> _toggleComplete(_MaintenanceTask task) async {
    setState(() {
      task.completed = !task.completed;
      task.completedAt = task.completed ? DateTime.now() : null;
    });
    await _save();
    if (mounted) {
      showAppNotification(
          task.completed
              ? '${task.name} marked complete.'
              : '${task.name} reopened.',
          tone: AppNotificationTone.success);
    }
  }

  Future<void> _addPhoto(_MaintenanceTask task, ImageSource source) async {
    final photo = await _picker.pickImage(
        source: source, imageQuality: 55, maxWidth: 900);
    if (photo == null) return;
    final bytes = await photo.readAsBytes();
    if (!mounted) return;
    setState(() => task.photos.add(bytes));
    await _save();
    showAppNotification('Photo attached to ${task.name}.',
        tone: AppNotificationTone.success);
  }

  void _showTask(_MaintenanceTask task) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(task.name,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(task.detail,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              Text('Photo evidence',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (task.photos.isEmpty)
                Text('No photos added yet.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              if (task.photos.isNotEmpty)
                SizedBox(
                    height: 112,
                    child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: task.photos.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, index) => ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(task.photos[index],
                                width: 112, height: 112, fit: BoxFit.cover)))),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => _addPhoto(task, ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Camera'))),
                const SizedBox(width: 12),
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => _addPhoto(task, ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Gallery'))),
              ]),
              const SizedBox(height: 12),
              FilledButton.icon(
                  onPressed: () {
                    _toggleComplete(task);
                    Navigator.pop(context);
                  },
                  icon: Icon(task.completed
                      ? Icons.restart_alt_rounded
                      : Icons.task_alt_rounded),
                  label:
                      Text(task.completed ? 'Reopen task' : 'Mark complete')),
            ])),
      )),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(20), children: [
                  Text('EQUIPMENT CARE',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1)),
                  const SizedBox(height: 4),
                  Text('Maintenance',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                      '${_tasks.where((task) => !task.completed).length} task(s) need attention',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 20),
                  ..._tasks.map((task) => Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        onTap: () => _showTask(task),
                        contentPadding: const EdgeInsets.all(16),
                        leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                                color: (task.completed
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFFF59E0B))
                                    .withValues(alpha: .15),
                                borderRadius: BorderRadius.circular(12)),
                            child: Icon(
                                task.completed
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.build_outlined,
                                color: task.completed
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFF59E0B))),
                        title: Text(task.name,
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                decoration: task.completed
                                    ? TextDecoration.lineThrough
                                    : null)),
                        subtitle: Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                                '${task.dueLabel} · ${task.photos.length} photo(s)')),
                        trailing: IconButton(
                            tooltip: task.completed
                                ? 'Reopen task'
                                : 'Mark complete',
                            onPressed: () => _toggleComplete(task),
                            icon: Icon(task.completed
                                ? Icons.restart_alt_rounded
                                : Icons.check_circle_rounded,
                                color: task.completed
                                    ? const Color(0xFF10B981)
                                    : null)),
                      ))),
                ])));
}

class _MaintenanceTask {
  _MaintenanceTask(
      {required this.name,
      required this.detail,
      required this.dueLabel,
      this.completed = false,
      this.completedAt,
      List<Uint8List>? photos})
      : photos = photos ?? [];
  final String name, detail, dueLabel;
  bool completed;
  DateTime? completedAt;
  final List<Uint8List> photos;
  factory _MaintenanceTask.fromJson(Map<String, dynamic> json) =>
      _MaintenanceTask(
          name: '${json['name']}',
          detail: '${json['detail']}',
          dueLabel: '${json['dueLabel']}',
          completed: json['completed'] == true,
          completedAt: json['completedAt'] == null
              ? null
              : DateTime.tryParse('${json['completedAt']}'),
          photos: ((json['photos'] as List?) ?? const [])
              .whereType<String>()
              .map(base64Decode)
              .toList());
  Map<String, dynamic> toJson() => {
        'name': name,
        'detail': detail,
        'dueLabel': dueLabel,
        'completed': completed,
        'completedAt': completedAt?.toIso8601String(),
        'photos': photos.map(base64Encode).toList()
      };
  static List<_MaintenanceTask> defaults() => [
        _MaintenanceTask(
            name: 'Espresso machine clean',
            detail: 'Backflush, wipe the group heads, and inspect seals.',
            dueLabel: 'Due today'),
        _MaintenanceTask(
            name: 'Walk-in chiller inspection',
            detail: 'Check temperature log, door seals, and condenser airflow.',
            dueLabel: 'Due tomorrow'),
        _MaintenanceTask(
            name: 'POS printer service',
            detail:
                'Clean print head and replace the paper-feed roller if worn.',
            dueLabel: 'Due Aug 24'),
      ];
}
