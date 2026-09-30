import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../services/secure_storage_service.dart';
import '../widgets/ui/ui.dart';
import 'app_notifications.dart';
import 'authenticated_api_client.dart';
import 'inventory_panel.dart';
import 'inventory_loading_state.dart';

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
  List<_MaintenanceEquipment> _equipment = const [];
  List<_MaintenanceBranch> _branches = const [];
  bool _loading = true;
  String? _loadError;
  bool _canManageEquipment = false;
  String? _tenantId;
  final Set<String> _updatingTaskIds = {};
  String _selectedTab = 'All'; // 'All', 'Pending', 'Completed'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showSuccess = false}) async {
    if (mounted) {
      setState(() {
        _loading = _tasks.isEmpty;
        _loadError = null;
      });
    }
    try {
      final storedUser = await SecureStorageService.getUser();
      final user = storedUser == null
          ? null
          : jsonDecode(storedUser) as Map<String, dynamic>;
      final tenantId = user?['tenantId']?.toString();
      if (tenantId == null || tenantId.isEmpty) {
        throw StateError('The signed-in account has no tenant information.');
      }
      final role = user?['role']?.toString();
      final canManageEquipment = role == 'Admin' || role == 'Manager';
      final userBranchId = user?['branchId']?.toString();

      final equipmentResponse = await widget.client
          .get('/api/equipment?tenantId=${Uri.encodeQueryComponent(tenantId)}');
      if (equipmentResponse.statusCode < 200 ||
          equipmentResponse.statusCode >= 300) {
        throw StateError(
          _apiError(equipmentResponse.body, equipmentResponse.statusCode),
        );
      }
      final equipmentData = jsonDecode(equipmentResponse.body) as List<dynamic>;
      final equipment = equipmentData
          .whereType<Map<String, dynamic>>()
          .map(_MaintenanceEquipment.fromApi)
          .toList();
      List<_MaintenanceBranch> branches = const [];
      if (canManageEquipment) {
        final branchResponse = await widget.client.get(
            '/api/branches?tenantId=${Uri.encodeQueryComponent(tenantId)}');
        if (branchResponse.statusCode < 200 ||
            branchResponse.statusCode >= 300) {
          throw StateError(
            _apiError(branchResponse.body, branchResponse.statusCode),
          );
        }
        branches = (jsonDecode(branchResponse.body) as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map(_MaintenanceBranch.fromApi)
            .where((branch) => role != 'Manager' || branch.id == userBranchId)
            .toList();
      }
      final response = await widget.client.get('/api/equipment-maintenance');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(_apiError(response.body, response.statusCode));
      }
      final data = jsonDecode(response.body) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _equipment = equipment;
        _branches = branches;
        _canManageEquipment = canManageEquipment;
        _tenantId = tenantId;
        _tasks = data
            .whereType<Map<String, dynamic>>()
            .map((json) => _MaintenanceTask.fromApi(json, equipment))
            .toList();
        _loadError = null;
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
      final detail = error is StateError
          ? error.message
          : 'Check that the backend is running and the signed-in account has access.';
      setState(() {
        _tasks = const [];
        _equipment = const [];
        _branches = const [];
        _loadError = detail;
        _loading = false;
      });
      showAppNotification(
        'Maintenance records could not be loaded. $detail',
        tone: AppNotificationTone.error,
        title: 'Maintenance unavailable',
      );
    }
  }

  String _apiError(String body, int statusCode) {
    try {
      final payload = jsonDecode(body);
      if (payload is Map<String, dynamic>) {
        final message = payload['message'] ?? payload['title'];
        if (message is String && message.trim().isNotEmpty) return message;
        final errors = payload['errors'];
        if (errors is Map<String, dynamic>) {
          final details = errors.values
              .whereType<List>()
              .expand((messages) => messages)
              .whereType<String>()
              .where((message) => message.trim().isNotEmpty)
              .join(' ');
          if (details.isNotEmpty) return details;
        }
      }
    } on FormatException {
      // Fall back to the HTTP status when the response is not JSON.
    }
    return 'Maintenance API returned $statusCode.';
  }

  Future<void> _addEquipment() async {
    if (!_canManageEquipment) return;
    final branches = _branches;
    if (branches.isEmpty) {
      showAppNotification(
        'Add an active branch to your business before adding equipment.',
        tone: AppNotificationTone.warning,
        title: 'No branch available',
      );
      return;
    }

    final nameController = TextEditingController();
    final categoryController = TextEditingController();
    final skuController = TextEditingController();
    final unitController = TextEditingController(text: 'unit');
    var selectedBranchId = branches.first.id;
    var submitting = false;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF111A31),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add equipment',
                    style: AppTextStyles.title
                        .copyWith(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Save an asset to this business so it can be scheduled for service.',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 18),
                  _formLabel('EQUIPMENT NAME'),
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 200,
                    style: const TextStyle(color: Colors.white),
                    decoration: _maintenanceInputDecoration(
                      hint: 'e.g. Generator, Dive tank, Wheelchair',
                    ),
                  ),
                  const SizedBox(height: 8),
                  _formLabel('BRANCH'),
                  DropdownButtonFormField<String>(
                    initialValue: selectedBranchId,
                    dropdownColor: const Color(0xFF17233A),
                    decoration: _maintenanceInputDecoration(),
                    items: branches
                        .map((branch) => DropdownMenuItem(
                              value: branch.id,
                              child: Text(
                                branch.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: submitting
                        ? null
                        : (value) {
                            if (value != null) {
                              setSheetState(() => selectedBranchId = value);
                            }
                          },
                  ),
                  const SizedBox(height: 14),
                  _formLabel('CATEGORY (OPTIONAL)'),
                  TextField(
                    controller: categoryController,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(color: Colors.white),
                    decoration:
                        _maintenanceInputDecoration(hint: 'e.g. Machinery'),
                  ),
                  const SizedBox(height: 14),
                  _formLabel('SKU (OPTIONAL)'),
                  TextField(
                    controller: skuController,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white),
                    decoration: _maintenanceInputDecoration(hint: 'Asset code'),
                  ),
                  const SizedBox(height: 14),
                  _formLabel('UNIT'),
                  TextField(
                    controller: unitController,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(color: Colors.white),
                    decoration: _maintenanceInputDecoration(hint: 'unit'),
                  ),
                  const SizedBox(height: 18),
                  NeonButton(
                    label: submitting ? 'Saving…' : 'Save equipment',
                    icon: Icons.save_rounded,
                    onPressed: submitting
                        ? null
                        : () async {
                            final name = nameController.text.trim();
                            if (name.isEmpty) {
                              showAppNotification(
                                'Enter an equipment name.',
                                tone: AppNotificationTone.warning,
                              );
                              return;
                            }
                            final tenantId = _tenantId;
                            if (tenantId == null || tenantId.isEmpty) {
                              showAppNotification(
                                'Your business session has expired. Sign in again and retry.',
                                tone: AppNotificationTone.error,
                              );
                              return;
                            }
                            setSheetState(() => submitting = true);
                            try {
                              final response = await widget.client
                                  .post('/api/equipment', body: {
                                'tenantId': tenantId,
                                'branchId': selectedBranchId,
                                'name': name,
                                'category': categoryController.text.trim(),
                                'sku': skuController.text.trim(),
                                'unit': unitController.text.trim().isEmpty
                                    ? 'unit'
                                    : unitController.text.trim(),
                                'currentStock': 0,
                                'reorderLevel': 0,
                                'costPrice': 0,
                                'sellingPrice': 0,
                              });
                              if (response.statusCode < 200 ||
                                  response.statusCode >= 300) {
                                throw StateError(_apiError(
                                  response.body,
                                  response.statusCode,
                                ));
                              }
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext, true);
                              }
                            } catch (error) {
                              showAppNotification(
                                'Could not save equipment. ${error is StateError ? error.message : 'Check your connection and permissions.'}',
                                tone: AppNotificationTone.error,
                              );
                            } finally {
                              if (sheetContext.mounted) {
                                setSheetState(() => submitting = false);
                              }
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    nameController.dispose();
    categoryController.dispose();
    skuController.dispose();
    unitController.dispose();
    if (created == true && mounted) {
      await _load();
      showAppNotification(
        'Equipment was saved to your business and is ready for maintenance scheduling.',
        tone: AppNotificationTone.success,
        title: 'Equipment added',
      );
    }
  }

  Future<void> _scheduleMaintenance() async {
    if (_equipment.isEmpty) {
      showAppNotification(
        'Add active equipment before scheduling maintenance.',
        tone: AppNotificationTone.warning,
        title: 'No equipment available',
      );
      return;
    }
    final notesController = TextEditingController();
    final costController = TextEditingController(text: '0');
    var isSubmitting = false;
    var selectedEquipmentId = _equipment.first.id;
    final today = DateTime.now();
    var maintenanceDate = DateTime(today.year, today.month, today.day);
    var nextDueDate = maintenanceDate.add(const Duration(days: 90));
    final shouldReload = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          decoration: const BoxDecoration(
            color: Color(0xFF111A31),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Schedule equipment service',
                      style: AppTextStyles.title
                          .copyWith(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                      'Choose equipment, record the service date, and set its next due date.',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 18),
                  _formLabel('EQUIPMENT'),
                  DropdownButtonFormField<String>(
                    initialValue: selectedEquipmentId,
                    dropdownColor: const Color(0xFF17233A),
                    decoration: _maintenanceInputDecoration(),
                    items: _equipment
                        .map((item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name,
                                overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setSheetState(() => selectedEquipmentId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                        child: _dateField('SERVICE DATE', maintenanceDate,
                            () async {
                      final picked = await showDatePicker(
                          context: context,
                          initialDate: maintenanceDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          builder: _datePickerTheme);
                      if (picked != null) {
                        setSheetState(() {
                          maintenanceDate = picked;
                          if (_dateOnly(nextDueDate)
                              .isBefore(_dateOnly(picked))) {
                            nextDueDate = picked;
                          }
                        });
                      }
                    })),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _dateField('NEXT DUE', nextDueDate, () async {
                      final picked = await showDatePicker(
                          context: context,
                          initialDate: nextDueDate,
                          firstDate: maintenanceDate,
                          lastDate: DateTime(2100),
                          builder: _datePickerTheme);
                      if (picked != null) {
                        setSheetState(() => nextDueDate = picked);
                      }
                    })),
                  ]),
                  const SizedBox(height: 14),
                  _formLabel('SERVICE COST'),
                  TextField(
                      controller: costController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: _maintenanceInputDecoration(hint: '0.00')),
                  const SizedBox(height: 14),
                  _formLabel('NOTES'),
                  TextField(
                      controller: notesController,
                      minLines: 2,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: _maintenanceInputDecoration(
                          hint:
                              'Work completed, parts replaced, observations…')),
                  const SizedBox(height: 18),
                  NeonButton(
                    label: isSubmitting ? 'Scheduling…' : 'Schedule service',
                    icon: Icons.event_available_rounded,
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final cost =
                                double.tryParse(costController.text.trim());
                            if (cost == null || !cost.isFinite || cost < 0) {
                              showAppNotification(
                                  'Enter a valid service cost (zero is allowed).',
                                  tone: AppNotificationTone.warning);
                              return;
                            }
                            if (_dateOnly(nextDueDate)
                                .isBefore(_dateOnly(maintenanceDate))) {
                              showAppNotification(
                                  'The next due date must be on or after the service date.',
                                  tone: AppNotificationTone.warning);
                              return;
                            }
                            setSheetState(() => isSubmitting = true);
                            try {
                              final response = await widget.client
                                  .post('/api/equipment-maintenance', body: {
                                'equipmentItemId': selectedEquipmentId,
                                'maintenanceDate':
                                    _maintenanceDatePayload(maintenanceDate),
                                'nextDueDate':
                                    _maintenanceDatePayload(nextDueDate),
                                'cost': cost,
                                'status': 'Scheduled',
                                'notes': notesController.text.trim().isEmpty
                                    ? null
                                    : notesController.text.trim(),
                              });
                              if (response.statusCode < 200 ||
                                  response.statusCode >= 300) {
                                throw StateError(_apiError(
                                    response.body, response.statusCode));
                              }
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext, true);
                              }
                              showAppNotification(
                                  'Service was added to the maintenance log.',
                                  tone: AppNotificationTone.success,
                                  title: 'Service scheduled');
                            } catch (error) {
                              showAppNotification(
                                  'Could not schedule service. ${error is StateError ? error.message : 'Check your connection and permissions.'}',
                                  tone: AppNotificationTone.error);
                            } finally {
                              if (sheetContext.mounted) {
                                setSheetState(() => isSubmitting = false);
                              }
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    notesController.dispose();
    costController.dispose();
    if (shouldReload == true && mounted) await _load();
  }

  Widget _formLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(label,
            style: AppTextStyles.label.copyWith(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
      );

  InputDecoration _maintenanceInputDecoration({String? hint}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textMuted.withValues(alpha: .8)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: .06),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: AppColors.glassBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: AppColors.cyan)),
      );

  Widget _dateField(String label, DateTime value, VoidCallback onTap) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _formLabel(label),
          InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 14),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: AppColors.glassBorder)),
              child: Row(children: [
                const Icon(Icons.calendar_month_rounded,
                    size: 17, color: AppColors.cyan),
                const SizedBox(width: 7),
                Expanded(
                    child: Text(_formatDate(value),
                        style:
                            AppTextStyles.caption.copyWith(color: Colors.white),
                        maxLines: 1))
              ]),
            ),
          ),
        ],
      );

  Widget _datePickerTheme(BuildContext context, Widget? child) => Theme(
        data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
                primary: AppColors.cyan, surface: Color(0xFF17233A))),
        child: child!,
      );

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String _maintenanceDatePayload(DateTime date) =>
      DateTime(date.year, date.month, date.day, 12).toUtc().toIso8601String();

  Future<bool> _toggleComplete(_MaintenanceTask task) async {
    if (!_updatingTaskIds.add(task.id)) return false;
    if (mounted) setState(() {});
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
          'The maintenance record could not be updated. ${_apiError(response.body, response.statusCode)}',
          tone: AppNotificationTone.error,
        );
        return false;
      }
    } catch (_) {
      showAppNotification(
        'The maintenance record could not be updated. Check the connection and try again.',
        tone: AppNotificationTone.error,
      );
      return false;
    } finally {
      if (mounted) {
        setState(() => _updatingTaskIds.remove(task.id));
      }
    }
    if (!mounted) return false;
    setState(() {
      task.completed = !task.completed;
      task.status = nextStatus;
    });
    showAppNotification(
      task.completed
          ? '${task.name} marked complete.'
          : '${task.name} reopened for inspection.',
      tone: AppNotificationTone.success,
    );
    return true;
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
      return _toggleComplete(task);
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
                        label: _updatingTaskIds.contains(task.id)
                            ? 'Saving…'
                            : task.completed
                                ? 'Reopen Inspection Task'
                                : 'Mark Task Complete',
                        icon: task.completed
                            ? Icons.restart_alt_rounded
                            : Icons.check_circle_rounded,
                        onPressed: _updatingTaskIds.contains(task.id)
                            ? null
                            : () async {
                                final completed =
                                    await _confirmToggleComplete(task);
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
    final dueCount = _tasks
        .where((t) => !t.completed && !t.nextDueDate.isAfter(DateTime.now()))
        .length;

    return AppBackgroundScaffold(
      showParticles: false,
      appBar: const GlassAppBar(
        title: 'Equipment Maintenance',
      ),
      child: SafeArea(
        child: _loading
            ? const InventoryLoadingState(
                message: 'Loading maintenance',
                detail: 'Preparing your equipment records',
              )
            : RefreshIndicator(
                color: AppColors.cyan,
                backgroundColor: AppColors.overlaySurface,
                onRefresh: () => _load(showSuccess: true),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    // Top Overview Card
                    _buildOverviewHeader(dueCount, completedCount),
                    const SizedBox(height: 18),

                    if (_loadError != null) ...[
                      _buildLoadError(),
                      const SizedBox(height: 16),
                    ],

                    if (_equipment.isEmpty) ...[
                      if (_canManageEquipment) ...[
                        SizedBox(
                          width: double.infinity,
                          child: NeonButton(
                            label: 'Add equipment to your business',
                            icon: Icons.add_box_rounded,
                            onPressed: _addEquipment,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (_loadError == null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _canManageEquipment
                                ? 'Equipment you add here is saved to the live business database and can then be scheduled for service.'
                                : 'Ask a Manager or Administrator to add equipment to this business.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.textMuted),
                          ),
                        ),
                    ] else ...[
                      SizedBox(
                        width: double.infinity,
                        child: NeonButton(
                          label: 'Schedule maintenance',
                          icon: Icons.add_rounded,
                          onPressed: _scheduleMaintenance,
                        ),
                      ),
                      if (_canManageEquipment) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton.icon(
                            onPressed: _addEquipment,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add equipment'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],

                    // Filter Tab Bar
                    _buildTabSwitcher(pendingCount, completedCount),
                    const SizedBox(height: 16),

                    if (_filteredTasks.isEmpty)
                      _tasks.isEmpty && _selectedTab == 'All'
                          ? EmptyState(
                              icon: Icons.handyman_outlined,
                              title: _equipment.isEmpty
                                  ? 'No equipment added yet'
                                  : 'Start your equipment care log',
                              message: _equipment.isEmpty
                                  ? _canManageEquipment
                                      ? 'Add equipment to the live business database using the button above. Then schedule its first service here.'
                                      : 'Ask a Manager or Administrator to add equipment to this business.'
                                  : 'No service is logged yet. Schedule a task to track service dates, costs, notes and photo evidence.',
                            )
                          : EmptyState(
                              icon: Icons.check_circle_outline_rounded,
                              title: _selectedTab == 'Pending'
                                  ? 'All caught up'
                                  : 'No completed tasks yet',
                              message: _selectedTab == 'Pending'
                                  ? 'There are no pending maintenance tasks.'
                                  : 'Completed service records will appear here.',
                            )
                    else
                      ..._filteredTasks.map((task) => _buildTaskCard(task)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildLoadError() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF43F5E).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFF43F5E).withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined,
                color: Color(0xFFFDA4AF), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Maintenance data is unavailable. $_loadError',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textPrimary),
              ),
            ),
            TextButton(
              onPressed: _loading ? null : _load,
              child: const Text('Retry'),
            ),
          ],
        ),
      );

  Widget _buildOverviewHeader(int pending, int completed) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: const Color(0xFF142235),
        border: Border.all(color: const Color(0xFF2A4058)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 16,
            offset: Offset(0, 7),
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
      child: InventoryPanel(
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
              onPressed: _updatingTaskIds.contains(task.id)
                  ? null
                  : () => _confirmToggleComplete(task),
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

  factory _MaintenanceTask.fromApi(
      Map<String, dynamic> json, List<_MaintenanceEquipment> equipment) {
    final nextDueDate =
        DateTime.tryParse(json['nextDueDate'] as String? ?? '') ??
            DateTime.now();
    final status = json['status'] as String? ?? 'Scheduled';
    final equipmentId = json['equipmentItemId'] as String? ?? '';
    final matchingEquipment = equipment.where((item) => item.id == equipmentId);
    final equipmentItem =
        matchingEquipment.isEmpty ? null : matchingEquipment.first;
    final photoUrls =
        (json['photoUrls'] as List? ?? const []).whereType<String>().toList();
    return _MaintenanceTask(
      id: json['id'] as String? ?? '',
      equipmentItemId: equipmentId,
      name: equipmentItem?.name ??
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

class _MaintenanceEquipment {
  const _MaintenanceEquipment(
      {required this.id, required this.name, required this.category});

  final String id;
  final String name;
  final String category;

  factory _MaintenanceEquipment.fromApi(Map<String, dynamic> json) =>
      _MaintenanceEquipment(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Unnamed equipment',
        category: json['category'] as String? ?? '',
      );
}

class _MaintenanceBranch {
  const _MaintenanceBranch({required this.id, required this.name});

  final String id;
  final String name;

  factory _MaintenanceBranch.fromApi(Map<String, dynamic> json) =>
      _MaintenanceBranch(
        id: json['id']?.toString() ?? '',
        name: json['name'] as String? ?? 'Unnamed branch',
      );
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
