import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';
import 'app_notifications.dart';
import 'authenticated_api_client.dart';
import 'inventory_models.dart';

enum StockOperation { checkIn, checkOut }

class StockCheckScreen extends StatefulWidget {
  const StockCheckScreen({super.key, required this.client});

  final AuthenticatedApiClient client;

  @override
  State<StockCheckScreen> createState() => _StockCheckScreenState();
}

class _StockCheckScreenState extends State<StockCheckScreen> {
  final _scanner = MobileScannerController();
  final _barcode = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  StockOperation _operation = StockOperation.checkIn;
  String? _scannedCode;
  bool _torchOn = false;
  bool _saving = false;
  List<InventoryItem> _availableItems = const [];

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    try {
      final items = await _fetchInventoryItems();
      if (mounted) setState(() => _availableItems = items);
    } catch (_) {
      if (mounted) setState(() => _availableItems = const []);
    }
  }

  Future<List<InventoryItem>> _fetchInventoryItems() async {
    final items = <InventoryItem>[];
    var page = 1;
    var totalPages = 1;
    while (page <= totalPages) {
      final response =
          await widget.client.get('/api/inventory?page=$page&pageSize=100');
      if (response.statusCode != 200) {
        throw StateError('Inventory API returned ${response.statusCode}.');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      totalPages = (payload['totalPages'] as num?)?.toInt() ?? 1;
      items.addAll(((payload['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(InventoryItem.fromJson));
      page++;
    }
    return items;
  }

  @override
  void dispose() {
    _scanner.dispose();
    _barcode.dispose();
    _quantity.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final value = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (value == null || value.isEmpty || value == _scannedCode) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _scannedCode = value;
      _barcode.text = value;
    });
    _scanner.stop();
  }

  Future<void> _scanAgain() async {
    setState(() => _scannedCode = null);
    await _scanner.start();
  }

  void _stepQuantity(int delta) {
    HapticFeedback.selectionClick();
    final current = int.tryParse(_quantity.text) ?? 1;
    final next = (current + delta).clamp(1, 99999);
    setState(() => _quantity.text = '$next');
  }

  Future<void> _submit() async {
    if (_saving) return;
    final code = _barcode.text.trim();
    final quantity = int.tryParse(_quantity.text);
    if (code.isEmpty || quantity == null || quantity <= 0) {
      showAppNotification(
        'Please enter or scan a valid SKU and specify a quantity greater than zero.',
        tone: AppNotificationTone.warning,
      );
      return;
    }

    final isCheckout = _operation == StockOperation.checkOut;
    final confirmed = await showAppConfirmation(
      context: context,
      title: isCheckout ? 'Confirm stock issue?' : 'Confirm stock receipt?',
      message: isCheckout
          ? 'Deduct $quantity unit(s) of SKU "$code" from the inventory ledger?'
          : 'Add $quantity unit(s) of SKU "$code" to the inventory ledger?',
      confirmLabel: isCheckout ? 'Issue Stock' : 'Receive Stock',
      icon: isCheckout
          ? Icons.remove_circle_outline_rounded
          : Icons.add_circle_outline_rounded,
      accent: isCheckout ? const Color(0xFFF43F5E) : const Color(0xFF34D399),
      isDestructive: isCheckout,
    );
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    try {
      final items = await _fetchInventoryItems();
      final matchingItem = items
          .where(
              (candidate) => candidate.sku.toLowerCase() == code.toLowerCase())
          .firstOrNull;
      if (matchingItem != null) {
        final endpoint = _operation == StockOperation.checkIn
            ? '/api/inventory/${matchingItem.id}/receive'
            : '/api/inventory/${matchingItem.id}/adjust';
        final response = await widget.client.post(
          endpoint,
          body: {
            'quantity':
                _operation == StockOperation.checkIn ? quantity : -quantity,
            'reference': 'MOBILE-SCANNER',
            'notes': 'Recorded from mobile barcode scanner',
          },
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (!mounted) return;
          showAppNotification(
            '${_operation == StockOperation.checkIn ? 'Check-in' : 'Check-out'} recorded for ${matchingItem.name} ($quantity units).',
            tone: AppNotificationTone.success,
          );
          setState(() {
            _saving = false;
            _scannedCode = null;
            _barcode.clear();
            _quantity.text = '1';
          });
          _loadPresets();
          return;
        }
        if (mounted) {
          setState(() => _saving = false);
          showAppNotification(
            'Inventory operation rejected by server (${response.statusCode}).',
            tone: AppNotificationTone.error,
          );
        }
        return;
      }
      if (mounted) {
        setState(() => _saving = false);
        showAppNotification(
          'No inventory item registered with SKU "$code".',
          tone: AppNotificationTone.error,
        );
      }
      return;
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAppNotification(
          e is StateError
              ? 'Inventory service unavailable. Check the backend and your access, then retry.'
              : 'Failed to connect to inventory service. Verify network connection.',
          tone: AppNotificationTone.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCheckIn = _operation == StockOperation.checkIn;
    final activeColor = isCheckIn ? AppColors.cyan : const Color(0xFFF43F5E);

    return AppBackgroundScaffold(
      showParticles: false,
      appBar: GlassAppBar(
        title: 'Stock Movements',
        actions: [
          IconButton(
            onPressed: _scanAgain,
            tooltip: 'Reset Scanner',
            icon: const Icon(Icons.qr_code_scanner_rounded,
                color: AppColors.cyan),
          ),
        ],
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // High-tech Dual Segment Pill Switcher
              _buildOperationSwitcher(isCheckIn),
              const SizedBox(height: 18),

              // Cyber Scanner Viewport
              _buildScannerViewport(activeColor),
              const SizedBox(height: 18),

              // Fast SKU Catalog Carousel
              if (_availableItems.isNotEmpty) ...[
                SectionHeader(
                  'REGISTERED CATALOG ITEMS',
                  trailing: Text('Tap to fill SKU',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.cyan)),
                ),
                _buildQuickItemCarousel(),
                const SizedBox(height: 18),
              ],

              // Input & Control Panel
              GlassCard(
                padding: const EdgeInsets.all(20),
                borderColor: activeColor.withValues(alpha: 0.35),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('ITEM CODE / SKU', style: AppTextStyles.label),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _barcode,
                      style: AppTextStyles.body.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                      onChanged: (value) => setState(
                          () => _scannedCode = value.isEmpty ? null : value),
                      decoration: InputDecoration(
                        hintText: 'Enter or scan SKU barcode...',
                        hintStyle: AppTextStyles.bodyMuted,
                        filled: true,
                        fillColor: AppColors.inputFill,
                        prefixIcon: Icon(Icons.qr_code_2_rounded,
                            color: activeColor, size: 22),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.glassBorder),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    Text('QUANTITY', style: AppTextStyles.label),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildStepButton(Icons.remove, () => _stepQuantity(-1)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _quantity,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            style: AppTextStyles.title.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.inputFill,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppColors.glassBorder),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStepButton(Icons.add, () => _stepQuantity(1)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Quick increment chips
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [1, 5, 10, 25, 50].map((amt) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                final current =
                                    int.tryParse(_quantity.text) ?? 0;
                                setState(
                                    () => _quantity.text = '${current + amt}');
                              },
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 7),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: AppColors.glassBorder),
                                ),
                                child: Center(
                                  child: Text(
                                    '+$amt',
                                    style: AppTextStyles.caption.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // Action Button
                    NeonButton(
                      label: _saving
                          ? 'Recording...'
                          : isCheckIn
                              ? 'Record Stock Check-In'
                              : 'Record Stock Check-Out',
                      isLoading: _saving,
                      icon: isCheckIn
                          ? Icons.add_circle_outline_rounded
                          : Icons.remove_circle_outline_rounded,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepButton(IconData icon, VoidCallback onTap) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Center(child: Icon(icon, color: Colors.white, size: 20)),
        ),
      ),
    );
  }

  Widget _buildOperationSwitcher(bool isCheckIn) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xE6080D20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _operation = StockOperation.checkIn);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: isCheckIn ? AppColors.buttonGradient : null,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isCheckIn
                      ? [
                          BoxShadow(
                            color: AppColors.cyan.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.arrow_downward_rounded,
                      size: 17,
                      color: isCheckIn ? Colors.white : AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Check-in (Receive)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.subtitle.copyWith(
                          color: isCheckIn
                              ? Colors.white
                              : AppColors.textSecondary,
                          fontWeight:
                              isCheckIn ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _operation = StockOperation.checkOut);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: !isCheckIn
                      ? const LinearGradient(
                          colors: [Color(0xFFFB7185), Color(0xFFE11D48)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: !isCheckIn
                      ? [
                          BoxShadow(
                            color:
                                const Color(0xFFE11D48).withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.arrow_upward_rounded,
                      size: 17,
                      color: !isCheckIn ? Colors.white : AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Check-out (Issue)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.subtitle.copyWith(
                          color: !isCheckIn
                              ? Colors.white
                              : AppColors.textSecondary,
                          fontWeight:
                              !isCheckIn ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerViewport(Color activeColor) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          border:
              Border.all(color: activeColor.withValues(alpha: 0.5), width: 1.5),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: activeColor.withValues(alpha: 0.16),
              blurRadius: 22,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _scanner,
              onDetect: _onDetect,
            ),
            _CyberScannerReticle(color: activeColor),
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xCC050A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: IconButton(
                  tooltip: _torchOn ? 'Turn Flash Off' : 'Turn Flash On',
                  onPressed: () async {
                    await _scanner.toggleTorch();
                    if (mounted) setState(() => _torchOn = !_torchOn);
                  },
                  icon: Icon(
                    _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    color: _torchOn ? AppColors.cyan : Colors.white70,
                    size: 20,
                  ),
                ),
              ),
            ),
            if (_scannedCode != null)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.8),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xF20B1028),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.cyan, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.cyan.withValues(alpha: 0.25),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_rounded,
                              color: AppColors.cyan, size: 36),
                          const SizedBox(height: 8),
                          Text('SKU Captured',
                              style:
                                  AppTextStyles.title.copyWith(fontSize: 16)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.cyan.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _scannedCode!,
                              style: AppTextStyles.subtitle.copyWith(
                                color: AppColors.cyan,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          GhostButton(
                            label: 'Scan Another Code',
                            onPressed: _scanAgain,
                            height: 38,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickItemCarousel() {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _availableItems.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = _availableItems[index];
          final isSelected =
              _barcode.text.trim().toLowerCase() == item.sku.toLowerCase();

          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _barcode.text = item.sku;
                _scannedCode = item.sku;
              });
            },
            child: Container(
              width: 160,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.cyan.withValues(alpha: 0.2)
                    : AppColors.glassFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? AppColors.cyan : AppColors.glassBorder,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.subtitle.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        item.sku,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        '${item.quantity.toInt()} left',
                        style: AppTextStyles.caption.copyWith(
                          color: item.isLowStock
                              ? const Color(0xFFF59E0B)
                              : AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CyberScannerReticle extends StatelessWidget {
  const _CyberScannerReticle({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 190,
          height: 150,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.2),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Stack(
            children: [
              // Center laser line
              Center(
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        color,
                        Colors.transparent,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(color: color, blurRadius: 6),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
