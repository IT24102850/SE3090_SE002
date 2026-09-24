import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';
import 'app_notifications.dart';
import 'authenticated_api_client.dart';

class EquipmentMaintenanceScreen extends StatefulWidget {
  const EquipmentMaintenanceScreen({super.key, required this.client});

  final AuthenticatedApiClient client;

  @override
  State<EquipmentMaintenanceScreen> createState() =>
      _EquipmentMaintenanceScreenState();
}

class _EquipmentMaintenanceScreenState
    extends State<EquipmentMaintenanceScreen> {
  final _picker = ImagePicker();
  List<_MaintenanceTask> _tasks = const [];
  bool _loading = true;
  String _selectedTab = 'All'; // 'All', 'Pending', 'Completed'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showSuccess = false}) async {
    try {
      final response = await widget.client.get('/api/equipment-maintenance');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Maintenance API returned ${response.statusCode}.');
      }
      final data = jsonDecode(response.body) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _tasks = data
            .whereType<Map<String, dynamic>>()
            .map(_MaintenanceTask.fromApi)
            .toList();
        _loading = false;
      });
      if (showSuccess) {
        showAppNotification(
          'Maintenance records refreshed successfully.',
          tone: AppNotificationTone.success,
          title: 'Records updated',
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _tasks = const [];
        _loading = false;
      });
      final detail = error is StateError
          ? error.message
          : 'Check that the backend is running and the signed-in account has access.';
      showAppNotification(
        'Maintenance records could not be loaded. $detail',
        tone: AppNotificationTone.error,
        title: 'Maintenance unavailable',
      );
    }
  }

  Future<void> _toggleComplete(_MaintenanceTask task) async {
    HapticFeedback.mediumImpact();
    final nextStatus = task.completed ? 'Scheduled' : 'Completed';
    try {
      final response = await widget.client.put(
        '/api/equipment-maintenance/${task.id}',
        body: {
          'equipmentItemId': task.equipmentItemId,
          'maintenanceDate': task.maintenanceDate.toUtc().toIso8601String(),
          'nextDueDate': task.nextDueDate.toUtc().toIso8601String(),
          'cost': task.cost,
          'status': nextStatus,
          'notes': task.notes,
          'photoUrls': task.photoUrls,
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        showAppNotification(
          'The maintenance record could not be updated (${response.statusCode}).',
          tone: AppNotificationTone.error,
        );
        return;
      }
    } catch (_) {
      showAppNotification(
        'The maintenance record could not be updated. Check the connection and try again.',
        tone: AppNotificationTone.error,
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      task.completed = !task.completed;
      task.status = nextStatus;
    });
    if (mounted) {
      showAppNotification(
        task.completed
            ? '${task.name} marked complete.'
            : '${task.name} reopened for inspection.',
        tone: AppNotificationTone.success,
      );
    }
  }

  Future<bool> _confirmToggleComplete(_MaintenanceTask task) async {
    final completing = !task.completed;
    final confirmed = await showAppConfirmation(
      context: context,
      title: completing
          ? 'Complete maintenance task?'
          : 'Reopen maintenance task?',
      message: completing
          ? 'Mark "${task.name}" as complete?'
          : 'Move "${task.name}" back to the pending inspection list?',
      confirmLabel: completing ? 'Mark Complete' : 'Reopen Task',
      icon: completing ? Icons.check_circle_rounded : Icons.restart_alt_rounded,
      accent: completing ? const Color(0xFF34D399) : AppColors.cyan,
    );
    if (confirmed && mounted) {
      await _toggleComplete(task);
      return true;
    }
    return false;
  }

  Future<void> _addPhoto(_MaintenanceTask task, ImageSource source) async {
    try {
      final photo = await _picker.pickImage(
        source: source,
        imageQuality: 60,
        maxWidth: 900,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      final url = await widget.client.uploadMaintenancePhoto(bytes, photo.name);
      final photoUrls = [...task.photoUrls, url];
      final response = await widget.client.put(
        '/api/equipment-maintenance/${task.id}',
        body: {
          'equipmentItemId': task.equipmentItemId,
          'maintenanceDate': task.maintenanceDate.toUtc().toIso8601String(),
          'nextDueDate': task.nextDueDate.toUtc().toIso8601String(),
          'cost': task.cost,
          'status': task.status,
          'notes': task.notes,
          'photoUrls': photoUrls,
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        showAppNotification(
          'The photo uploaded, but could not be attached to this maintenance record (${response.statusCode}).',
          tone: AppNotificationTone.error,
        );
        return;
      }
      if (!mounted) return;
      setState(() => task.photoUrls = photoUrls);
      showAppNotification(
        'Photo evidence attached to ${task.name}.',
        tone: AppNotificationTone.success,
      );
    } catch (_) {
      if (!mounted) return;
      showAppNotification(
        'Could not upload the photo. Check the connection, image service configuration, and access permissions.',
        tone: AppNotificationTone.error,
      );
    }
  }

  void _showTask(_MaintenanceTask task) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
              decoration: BoxDecoration(
                color: const Color(0xF50B1028),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.name,
                                  style: AppTextStyles.title.copyWith(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.schedule_rounded,
                                        size: 14, color: AppColors.cyan),
                                    const SizedBox(width: 4),
                                    Text(
                                      task.dueLabel,
                                      style: AppTextStyles.caption
                                          .copyWith(color: AppColors.cyan),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (task.completed
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFF59E0B))
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: (task.completed
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFFF59E0B))
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              task.completed ? 'COMPLETED' : 'PENDING ACTION',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: task.completed
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFFBBF24),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        task.detail,
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 22),

                      SectionHeader(
                        'PHOTO LOG EVIDENCE',
                        trailing: Text('${task.photoUrls.length} saved',
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.cyan)),
                      ),
                      const SizedBox(height: 10),

                      if (task.photoUrls.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.glassFill,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: Text(
                            'No photo evidence attached yet.',
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.textMuted),
                          ),
                        )
                      else
                        SizedBox(
                          height: 110,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: task.photoUrls.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (_, index) => ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: AppColors.cyan
                                          .withValues(alpha: 0.3)),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Image.network(
                                  task.photoUrls[index],
                                  width: 110,
                                  height: 110,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox(
                                    width: 110,
                                    height: 110,
                                    child: Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),

                      // Camera / Gallery Buttons
                      Row(
                        children: [
                          Expanded(
                            child: GhostButton(
                              label: 'Camera',
                              icon: Icons.camera_alt_rounded,
                              height: 46,
                              onPressed: () async {
                                await _addPhoto(task, ImageSource.camera);
                                setSheetState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GhostButton(
                              label: 'Gallery',
                              icon: Icons.photo_library_rounded,
                              height: 46,
                              onPressed: () async {
                                await _addPhoto(task, ImageSource.gallery);
                                setSheetState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      NeonButton(
                        label: task.completed
                            ? 'Reopen Inspection Task'
                            : 'Mark Task Complete',
                        icon: task.completed
                            ? Icons.restart_alt_rounded
                            : Icons.check_circle_rounded,
                        onPressed: () async {
                          final completed = await _confirmToggleComplete(task);
                          if (completed && bottomSheetContext.mounted) {
                            Navigator.pop(bottomSheetContext);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<_MaintenanceTask> get _filteredTasks {
    if (_selectedTab == 'Pending') {
      return _tasks.where((t) => !t.completed).toList();
    }
    if (_selectedTab == 'Completed') {
      return _tasks.where((t) => t.completed).toList();
    }
    return _tasks;
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _tasks.where((t) => !t.completed).length;
    final completedCount = _tasks.where((t) => t.completed).length;

    return AppBackgroundScaffold(
      showParticles: false,
      appBar: const GlassAppBar(
        title: 'Equipment Maintenance',
      ),
      child: SafeArea(
        child: _loading
            ? const AppLoader(message: 'Loading asset maintenance logs...')
            : RefreshIndicator(
                color: AppColors.cyan,
                backgroundColor: AppColors.overlaySurface,
                onRefresh: () => _load(showSuccess: true),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    // Top Overview Card
                    _buildOverviewHeader(pendingCount, completedCount),
                    const SizedBox(height: 18),

                    // Filter Tab Bar
                    _buildTabSwitcher(pendingCount, completedCount),
                    const SizedBox(height: 16),

                    if (_filteredTasks.isEmpty)
                      EmptyState(
                        icon: Icons.check_circle_outline_rounded,
                        title: 'No maintenance tasks',
                        message: _selectedTab == 'Pending'
                            ? 'All equipment inspections are up to date!'
                            : 'No completed tasks in log yet.',
                      )
                    else
                      ..._filteredTasks.map((task) => _buildTaskCard(task)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildOverviewHeader(int pending, int completed) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E1B4B),
            Color(0xFF14243B),
            Color(0xFF0F172A),
          ],
        ),
        border: Border.all(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'ASSET CARE & PREVENTIVE LOGS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.label.copyWith(
                    color: const Color(0xFFFBBF24),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_tasks.length} Tracked Tasks',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Machinery & Equipment Service',
            style: AppTextStyles.title
                .copyWith(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Keep appliances, espresso machines, refrigeration & POS hardware in peak condition.',
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.pending_actions_rounded,
                          size: 18, color: Color(0xFFFBBF24)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '$pending Due Now',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.subtitle.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFFBBF24),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 18, color: Color(0xFF10B981)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '$completed Completed',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.subtitle.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher(int pending, int completed) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          _buildPillTab('All', _tasks.length),
          _buildPillTab('Pending', pending),
          _buildPillTab('Completed', completed),
        ],
      ),
    );
  }

  Widget _buildPillTab(String label, int count) {
    final isSelected = _selectedTab == label;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedTab = label);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.cyan.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.cyan : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.cyan.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.white : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(_MaintenanceTask task) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        borderColor: task.completed
            ? const Color(0xFF10B981).withValues(alpha: 0.3)
            : const Color(0xFFF59E0B).withValues(alpha: 0.3),
        onTap: () => _showTask(task),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (task.completed
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B))
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (task.completed
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B))
                      .withValues(alpha: 0.35),
                ),
              ),
              child: Icon(
                task.completed
                    ? Icons.check_circle_rounded
                    : Icons.build_rounded,
                color: task.completed
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF59E0B),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.subtitle.copyWith(
                      fontWeight: FontWeight.w700,
                      decoration:
                          task.completed ? TextDecoration.lineThrough : null,
                      color: task.completed
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          task.dueLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(
                            color: task.completed
                                ? AppColors.textMuted
                                : AppColors.cyan,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (task.photoUrls.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.photo_camera_rounded,
                            size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            '${task.photoUrls.length} photo${task.photoUrls.length == 1 ? '' : 's'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                task.completed
                    ? Icons.restart_alt_rounded
                    : Icons.check_circle_outline_rounded,
                color: task.completed
                    ? AppColors.textMuted
                    : const Color(0xFF10B981),
              ),
              tooltip: task.completed ? 'Reopen Task' : 'Mark Complete',
              onPressed: () => _confirmToggleComplete(task),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaintenanceTask {
  _MaintenanceTask({
    required this.id,
    required this.equipmentItemId,
    required this.name,
    required this.detail,
    required this.notes,
    required this.dueLabel,
    required this.maintenanceDate,
    required this.nextDueDate,
    required this.cost,
    required this.status,
    this.completed = false,
    List<String>? photoUrls,
  }) : photoUrls = photoUrls ?? [];

  final String id;
  final String equipmentItemId;
  final String name, detail, dueLabel;
  final String? notes;
  final DateTime maintenanceDate;
  final DateTime nextDueDate;
  final double cost;
  String status;
  bool completed;
  List<String> photoUrls;

  factory _MaintenanceTask.fromApi(Map<String, dynamic> json) {
    final nextDueDate =
        DateTime.tryParse(json['nextDueDate'] as String? ?? '') ??
            DateTime.now();
    final status = json['status'] as String? ?? 'Scheduled';
    final equipmentId = json['equipmentItemId'] as String? ?? '';
    final photoUrls =
        (json['photoUrls'] as List? ?? const []).whereType<String>().toList();
    return _MaintenanceTask(
      id: json['id'] as String? ?? '',
      equipmentItemId: equipmentId,
      name:
          'Equipment ${equipmentId.length > 8 ? equipmentId.substring(0, 8) : equipmentId}',
      detail: json['notes'] as String? ?? 'No maintenance notes recorded.',
      notes: json['notes'] as String?,
      dueLabel: 'Due ${_formatDate(nextDueDate)}',
      maintenanceDate:
          DateTime.tryParse(json['maintenanceDate'] as String? ?? '') ??
              DateTime.now(),
      nextDueDate: nextDueDate,
      cost: (json['cost'] as num?)?.toDouble() ?? 0,
      status: status,
      completed: status.toLowerCase() == 'completed',
      photoUrls: photoUrls,
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
