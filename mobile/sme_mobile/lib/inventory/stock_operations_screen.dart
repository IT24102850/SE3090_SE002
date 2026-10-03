import 'dart:convert';

import 'package:flutter/material.dart';
import 'inventory_scaffold.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';
import 'app_notifications.dart';
import 'authenticated_api_client.dart';
import 'inventory_models.dart';
import 'inventory_panel.dart';
import 'inventory_loading_state.dart';

class StockOperationsScreen extends StatefulWidget {
  const StockOperationsScreen({super.key, required this.client});

  final AuthenticatedApiClient client;

  @override
  State<StockOperationsScreen> createState() => _StockOperationsScreenState();
}

class _StockOperationsScreenState extends State<StockOperationsScreen> {
  final _skuController = TextEditingController();
  final _quantityController = TextEditingController();
  final _scannerController = MobileScannerController(autoStart: false);
  List<InventoryItem> _items = const [];
  String? _selectedItemId;
  String? _error;
  String? _scannedSku;
  bool _receiveStock = true;
  bool _loading = true;
  bool _submitting = false;
  bool _scannerOpen = false;
  bool _handlingBarcode = false;

  List<InventoryItem> get _matches {
    final sku = _skuController.text.trim().toLowerCase();
    if (sku.isEmpty) return const [];
    return _items.where((item) => item.sku.toLowerCase() == sku).toList();
  }

  InventoryItem? get _selectedItem {
    final matches = _matches;
    if (_selectedItemId != null) {
      for (final item in matches) {
        if (item.id == _selectedItemId) return item;
      }
    }

    return matches.length == 1 ? matches.first : null;
  }

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _skuController.dispose();
    _quantityController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = <InventoryItem>[];
      var page = 1;
      var totalPages = 1;
      do {
        final response =
            await widget.client.get('/api/inventory?page=$page&pageSize=100');
        if (response.statusCode != 200) {
          throw StateError(
              'Could not load inventory items (server ${response.statusCode}).');
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        items.addAll(((data['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(InventoryItem.fromJson));
        totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
        page++;
      } while (page <= totalPages);
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is StateError
              ? error.message
              : 'Could not reach inventory. Check the network and retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSkuChanged(String value) {
    setState(() {
      _selectedItemId = null;
      if (_scannedSku != value.trim()) _scannedSku = null;
    });
  }

  Future<void> _openScanner() async {
    if (_scannerOpen) return;
    setState(() => _scannerOpen = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      await _scannerController.start();
    } catch (error) {
      if (!mounted) return;
      setState(() => _scannerOpen = false);
      showAppNotification(
        'Could not open the camera. Check camera permission and try again. $error',
        tone: AppNotificationTone.error,
      );
    }
  }

  Future<void> _closeScanner() async {
    if (!_scannerOpen) return;
    setState(() => _scannerOpen = false);
    try {
      await _scannerController.stop();
    } catch (error) {
      showAppNotification(
        'Could not stop the camera scanner: $error',
        tone: AppNotificationTone.error,
      );
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handlingBarcode) return;
    final code = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (code == null || code.isEmpty) return;
    _handlingBarcode = true;
    HapticFeedback.mediumImpact();
    setState(() {
      _skuController.text = code;
      _selectedItemId = null;
      _scannedSku = code;
      _scannerOpen = false;
    });
    try {
      await _scannerController.stop();
    } catch (error) {
      showAppNotification(
        'The barcode was captured, but the camera could not be stopped: $error',
        tone: AppNotificationTone.warning,
      );
    } finally {
      _handlingBarcode = false;
    }
    showAppNotification(
      'Barcode captured. Confirm the branch and quantity before changing stock.',
      tone: AppNotificationTone.success,
    );
  }

  Future<void> _toggleTorch() async {
    try {
      await _scannerController.toggleTorch();
    } catch (error) {
      showAppNotification(
        'Could not change the camera light: $error',
        tone: AppNotificationTone.error,
      );
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _scannerController.switchCamera();
    } catch (error) {
      showAppNotification(
        'Could not switch cameras: $error',
        tone: AppNotificationTone.error,
      );
    }
  }

  Widget _buildStepHeading(String number, String title) {
    return Row(
      children: [
        Container(
          width: 25,
          height: 25,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.cyan.withValues(alpha: .12),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.cyan.withValues(alpha: .35)),
          ),
          child: Text(
            number,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.cyan,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          title,
          style: AppTextStyles.subtitle.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildAnimatedSwitcher({required Widget child}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .035),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildMovementChoice({
    required bool receive,
    required String title,
    required String detail,
    required IconData icon,
  }) {
    final selected = _receiveStock == receive;
    final accent = receive ? AppColors.success : AppColors.warning;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $detail',
      child: Material(
        color: selected ? accent.withValues(alpha: .12) : AppColors.inputFill,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: Key('stock-operations-mode-${receive ? 'in' : 'out'}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            if (_receiveStock == receive) return;
            HapticFeedback.selectionClick();
            setState(() => _receiveStock = receive);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: .8)
                    : AppColors.glassBorder,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: accent, size: 20),
                    const Spacer(),
                    _buildAnimatedSwitcher(
                      child: selected
                          ? Icon(
                              Icons.check_circle_rounded,
                              key: const ValueKey('selected'),
                              color: accent,
                              size: 17,
                            )
                          : const SizedBox(
                              key: ValueKey('not-selected'),
                              width: 17,
                              height: 17,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  title,
                  style: AppTextStyles.subtitle.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _quantityHelperText(InventoryItem item) {
    final quantity = double.tryParse(_quantityController.text.trim());
    if (quantity == null || !quantity.isFinite || quantity <= 0) {
      return 'Available now: ${_formatQuantity(item.quantity)} ${item.unit}';
    }
    final updated =
        _receiveStock ? item.quantity + quantity : item.quantity - quantity;
    return 'Available now: ${_formatQuantity(item.quantity)} ${item.unit} · '
        'After: ${_formatQuantity(updated)} ${item.unit}';
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final receive = _receiveStock;
    final item = _selectedItem;
    final quantity = double.tryParse(_quantityController.text.trim());
    if (item == null) {
      showAppNotification(
        _matches.isEmpty
            ? 'Scan or enter a SKU that exists in inventory.'
            : 'Select the correct branch for this SKU.',
        tone: AppNotificationTone.warning,
      );
      return;
    }
    if (item.branchId == null) {
      showAppNotification(
        'Assign this item to a branch before changing its stock.',
        tone: AppNotificationTone.warning,
      );
      return;
    }
    if (quantity == null || !quantity.isFinite || quantity <= 0) {
      showAppNotification(
        'Enter a valid quantity greater than zero.',
        tone: AppNotificationTone.warning,
      );
      return;
    }
    if (!receive && quantity > item.quantity) {
      showAppNotification(
        'Cannot check out more than ${_formatQuantity(item.quantity)} ${item.unit} currently in stock.',
        tone: AppNotificationTone.warning,
      );
      return;
    }

    final confirmed = await showAppConfirmation(
      context: context,
      title: receive ? 'Confirm stock check-in?' : 'Confirm stock check-out?',
      message:
          '${receive ? 'Add' : 'Remove'} ${_formatQuantity(quantity)} ${item.unit} ${receive ? 'to' : 'from'} ${item.name} at ${item.branch}?',
      confirmLabel: receive ? 'Check in' : 'Check out',
      icon: receive ? Icons.add_box_outlined : Icons.outbox_outlined,
      accent: receive ? AppColors.success : AppColors.warning,
    );
    if (!confirmed || !mounted) return;

    setState(() => _submitting = true);
    try {
      final response = await widget.client.post(
        '/api/inventory/${item.id}/${receive ? 'receive' : 'issue'}',
        body: {
          'quantity': quantity,
          'reference': 'MOBILE-SCAN-${DateTime.now().microsecondsSinceEpoch}',
          'notes': receive
              ? 'Checked in from mobile stock operations.'
              : 'Checked out from mobile stock operations.',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = _responseMessage(response.body);
        showAppNotification(
          message ??
              'Stock ${receive ? 'check-in' : 'check-out'} failed (server ${response.statusCode}).',
          tone: AppNotificationTone.error,
        );
        return;
      }
      showAppNotification(
        '${_formatQuantity(quantity)} ${item.unit} ${receive ? 'checked in' : 'checked out'} for ${item.name}.',
        tone: AppNotificationTone.success,
      );
      _quantityController.clear();
      await _loadItems();
    } catch (error) {
      showAppNotification(
        'Could not complete the stock operation: $error',
        tone: AppNotificationTone.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _responseMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded['message'] as String? ?? decoded['title'] as String?;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  String _formatQuantity(double value) =>
      value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final item = _selectedItem;
    return InventoryScaffold(
      showParticles: false,
      appBar: GlassAppBar(
        title: 'Stock In / Out',
        actions: [
          IconButton(
            tooltip: 'Refresh inventory',
            onPressed: _loading ? null : _loadItems,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.cyan),
          ),
        ],
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, progress, child) => Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, (1 - progress) * 14),
            child: child,
          ),
        ),
        child: SafeArea(
          child: _buildAnimatedSwitcher(
            child: _loading && _items.isEmpty
                ? const InventoryLoadingState(
                    key: ValueKey('stock-operations-loading'),
                    message: 'Loading inventory',
                  )
                : _error != null && _items.isEmpty
                    ? Center(
                        key: const ValueKey('stock-operations-error'),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _loadItems,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        key: const ValueKey('stock-operations-content'),
                        padding: const EdgeInsets.all(16),
                        children: [
                          InventoryPanel(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(15),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.cyan.withValues(alpha: .14),
                                        AppColors.violet.withValues(alpha: .10),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(
                                      color:
                                          AppColors.cyan.withValues(alpha: .2),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 46,
                                        height: 46,
                                        decoration: BoxDecoration(
                                          color: AppColors.cyan
                                              .withValues(alpha: .13),
                                          borderRadius:
                                              BorderRadius.circular(13),
                                        ),
                                        child: const Icon(
                                          Icons.swap_vert_rounded,
                                          color: AppColors.cyan,
                                          size: 25,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Move stock',
                                              style:
                                                  AppTextStyles.title.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              'Choose an action, find an item, then confirm the quantity.',
                                              style: AppTextStyles.caption
                                                  .copyWith(
                                                color: AppColors.textSecondary,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _buildStepHeading('1', 'Choose an action'),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildMovementChoice(
                                        receive: true,
                                        title: 'Stock In',
                                        detail: 'Receive or add stock',
                                        icon: Icons.south_west_rounded,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _buildMovementChoice(
                                        receive: false,
                                        title: 'Stock Out',
                                        detail: 'Issue or remove stock',
                                        icon: Icons.north_east_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                _buildStepHeading('2', 'Find your item'),
                                const SizedBox(height: 10),
                                TextField(
                                  key: const Key('stock-operations-sku'),
                                  controller: _skuController,
                                  onChanged: _onSkuChanged,
                                  textInputAction: TextInputAction.search,
                                  decoration: InputDecoration(
                                    labelText: 'Enter or scan the item SKU',
                                    hintText: 'For example, SKU-00016',
                                    prefixIcon:
                                        const Icon(Icons.qr_code_2_rounded),
                                    suffixIcon: IconButton(
                                      tooltip: 'Clear SKU',
                                      onPressed: () {
                                        _skuController.clear();
                                        _onSkuChanged('');
                                      },
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                                  ),
                                ),
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.topCenter,
                                  child: _buildAnimatedSwitcher(
                                    child: _scannedSku != null &&
                                            _scannedSku ==
                                                _skuController.text.trim()
                                        ? const Row(
                                            key: ValueKey('scan-success'),
                                            children: [
                                              Icon(
                                                Icons.verified_rounded,
                                                color: AppColors.success,
                                                size: 17,
                                              ),
                                              SizedBox(width: 6),
                                              Text(
                                                'Barcode captured',
                                                key: Key(
                                                  'stock-operations-scan-success',
                                                ),
                                                style: TextStyle(
                                                  color: AppColors.success,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          )
                                        : const SizedBox.shrink(
                                            key: ValueKey('scan-not-captured'),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.topCenter,
                                  child: _buildAnimatedSwitcher(
                                    child: !_scannerOpen
                                        ? FilledButton.icon(
                                            key: const Key(
                                                'stock-operations-open-scanner'),
                                            onPressed: _openScanner,
                                            style: FilledButton.styleFrom(
                                              backgroundColor: AppColors.cyan,
                                              foregroundColor:
                                                  const Color(0xFF101521),
                                              minimumSize:
                                                  const Size.fromHeight(48),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(13),
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.qr_code_scanner_rounded,
                                              color: Color(0xFF101521),
                                            ),
                                            label: Text(
                                              'Open camera scanner',
                                              style:
                                                  AppTextStyles.button.copyWith(
                                                color: const Color(0xFF101521),
                                              ),
                                            ),
                                          )
                                        : SizedBox(
                                            key: const ValueKey(
                                                'stock-operations-scanner-view'),
                                            height: 240,
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  MobileScanner(
                                                    controller:
                                                        _scannerController,
                                                    onDetect: _onDetect,
                                                  ),
                                                  const IgnorePointer(
                                                    child: Center(
                                                      child: _ScannerReticle(),
                                                    ),
                                                  ),
                                                  Positioned(
                                                    top: 8,
                                                    right: 8,
                                                    child: Row(
                                                      children: [
                                                        _ScannerControlButton(
                                                          key: const Key(
                                                              'stock-operations-toggle-torch'),
                                                          tooltip:
                                                              'Toggle camera light',
                                                          icon: Icons
                                                              .flash_on_rounded,
                                                          onPressed:
                                                              _toggleTorch,
                                                        ),
                                                        const SizedBox(
                                                            width: 8),
                                                        _ScannerControlButton(
                                                          key: const Key(
                                                              'stock-operations-switch-camera'),
                                                          tooltip:
                                                              'Switch camera',
                                                          icon: Icons
                                                              .cameraswitch_rounded,
                                                          onPressed:
                                                              _switchCamera,
                                                        ),
                                                        const SizedBox(
                                                            width: 8),
                                                        _ScannerControlButton(
                                                          key: const Key(
                                                              'stock-operations-close-scanner'),
                                                          tooltip:
                                                              'Close camera scanner',
                                                          icon: Icons
                                                              .close_rounded,
                                                          onPressed:
                                                              _closeScanner,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Positioned(
                                                    left: 12,
                                                    right: 12,
                                                    bottom: 10,
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 12,
                                                        vertical: 8,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: AppColors
                                                            .overlaySurface
                                                            .withValues(
                                                                alpha: .9),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(20),
                                                        border: Border.all(
                                                          color: AppColors
                                                              .glassBorder,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        'Place the barcode inside the frame',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: AppTextStyles
                                                            .caption
                                                            .copyWith(
                                                          color: AppColors
                                                              .textPrimary,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                                if (matches.length > 1) ...[
                                  const SizedBox(height: 14),
                                  DropdownButtonFormField<String>(
                                    key: const Key('stock-operations-branch'),
                                    initialValue: matches.any((candidate) =>
                                            candidate.id == _selectedItemId)
                                        ? _selectedItemId
                                        : null,
                                    decoration: const InputDecoration(
                                      labelText: 'Select branch *',
                                    ),
                                    items: matches
                                        .map((candidate) =>
                                            DropdownMenuItem<String>(
                                              value: candidate.id,
                                              child: Text(
                                                '${candidate.branch} · ${_formatQuantity(candidate.quantity)} ${candidate.unit}',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ))
                                        .toList(),
                                    onChanged: (value) =>
                                        setState(() => _selectedItemId = value),
                                  ),
                                ],
                                _buildAnimatedSwitcher(
                                  child: matches.isEmpty &&
                                          _skuController.text.trim().isNotEmpty
                                      ? const Padding(
                                          key: ValueKey('no-matching-item'),
                                          padding: EdgeInsets.only(top: 12),
                                          child: Text(
                                            'No matching inventory item. Check the SKU or refresh inventory.',
                                            key: Key(
                                                'stock-operations-no-match'),
                                          ),
                                        )
                                      : const SizedBox.shrink(
                                          key: ValueKey('matching-item'),
                                        ),
                                ),
                                if (item != null) ...[
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: AppColors.glassFill,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: AppColors.glassBorder),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.inventory_2_outlined,
                                              color: AppColors.cyan,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 9),
                                            Expanded(
                                              child: Text(
                                                item.name,
                                                style: AppTextStyles.subtitle
                                                    .copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 9,
                                                vertical: 5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppColors.cyan
                                                    .withValues(alpha: .1),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                '${_formatQuantity(item.quantity)} ${item.unit}',
                                                style: AppTextStyles.caption
                                                    .copyWith(
                                                  color: AppColors.cyan,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${item.sku}  ·  ${item.branch}',
                                          style: AppTextStyles.caption.copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  _buildStepHeading('3', 'Enter quantity'),
                                  const SizedBox(height: 10),
                                  TextField(
                                    key: const Key('stock-operations-quantity'),
                                    controller: _quantityController,
                                    onChanged: (_) => setState(() {}),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d*\.?\d*')),
                                    ],
                                    decoration: InputDecoration(
                                      labelText:
                                          'Quantity to ${_receiveStock ? 'add' : 'remove'}',
                                      suffixText: item.unit,
                                      prefixIcon:
                                          const Icon(Icons.numbers_rounded),
                                      helper: _buildAnimatedSwitcher(
                                        child: Text(
                                          _quantityHelperText(item),
                                          key: ValueKey(
                                            _quantityHelperText(item),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  FilledButton.icon(
                                    key: const Key('stock-operations-submit'),
                                    onPressed: _submitting ? null : _submit,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _receiveStock
                                          ? AppColors.success
                                          : AppColors.warning,
                                      foregroundColor: const Color(0xFF101521),
                                      minimumSize: const Size.fromHeight(52),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    icon: AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 220),
                                      transitionBuilder: (child, animation) =>
                                          ScaleTransition(
                                        scale: animation,
                                        child: child,
                                      ),
                                      child: _submitting
                                          ? const SizedBox(
                                              key: ValueKey('submitting'),
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Color(0xFF101521),
                                              ),
                                            )
                                          : Icon(
                                              key: ValueKey(
                                                _receiveStock ? 'in' : 'out',
                                              ),
                                              _receiveStock
                                                  ? Icons.add_box_rounded
                                                  : Icons.outbox_rounded,
                                            ),
                                    ),
                                    label: AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 220),
                                      transitionBuilder: (child, animation) =>
                                          FadeTransition(
                                        opacity: animation,
                                        child: SlideTransition(
                                          position: Tween<Offset>(
                                            begin: const Offset(0, .12),
                                            end: Offset.zero,
                                          ).animate(animation),
                                          child: child,
                                        ),
                                      ),
                                      child: Text(
                                        _submitting
                                            ? 'Saving stock change...'
                                            : _receiveStock
                                                ? 'Review Stock In'
                                                : 'Review Stock Out',
                                        key: ValueKey(
                                          _submitting
                                              ? 'saving'
                                              : _receiveStock
                                                  ? 'review-in'
                                                  : 'review-out',
                                        ),
                                        style: AppTextStyles.button.copyWith(
                                          color: const Color(0xFF101521),
                                        ),
                                      ),
                                    ),
                                  ),
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutCubic,
                                    child: _submitting
                                        ? const Padding(
                                            padding: EdgeInsets.only(top: 14),
                                            child: LinearProgressIndicator(),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Your change is saved to stock activity after you review and confirm it.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
          ),
        ),
      ),
    );
  }
}

class _ScannerControlButton extends StatelessWidget {
  const _ScannerControlButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.overlaySurface.withValues(alpha: .9),
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.glassBorder),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}

class _ScannerReticle extends StatefulWidget {
  const _ScannerReticle();

  @override
  State<_ScannerReticle> createState() => _ScannerReticleState();
}

class _ScannerReticleState extends State<_ScannerReticle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final progress = _pulse.value;
        return Transform.scale(
          scale: .97 + progress * .06,
          child: Container(
            width: 210,
            height: 140,
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.cyan.withValues(alpha: .6 + progress * .4),
                width: 2.5,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.cyan.withValues(alpha: .18 + progress * .2),
                  blurRadius: 14 + progress * 10,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
