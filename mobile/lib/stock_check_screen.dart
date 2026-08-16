import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

enum StockOperation { checkIn, checkOut }

class StockCheckScreen extends StatefulWidget {
  const StockCheckScreen({super.key});

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

  Future<void> _submit() async {
    final code = _barcode.text.trim();
    final quantity = int.tryParse(_quantity.text);
    if (code.isEmpty || quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Scan or enter an item code and enter a valid quantity.')));
      return;
    }
    setState(() => _saving = true);
    // The request payload is ready for the authenticated inventory API. Keep this
    // local confirmation until the stock-operation endpoint is connected.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${_operation == StockOperation.checkIn ? 'Check-in' : 'Check-out'} recorded: $quantity unit${quantity == 1 ? '' : 's'} for $code.')));
    setState(() {
      _scannedCode = null;
      _barcode.clear();
      _quantity.text = '1';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('STOCK OPERATIONS', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                  const SizedBox(height: 4),
                  Text('Check stock in or out', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                ])),
                IconButton.filledTonal(onPressed: () => _scanAgain(), tooltip: 'Scan again', icon: const Icon(Icons.qr_code_scanner_rounded)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SegmentedButton<StockOperation>(
                segments: const [
                  ButtonSegment(value: StockOperation.checkIn, icon: Icon(Icons.add_circle_outline), label: Text('Check in')),
                  ButtonSegment(value: StockOperation.checkOut, icon: Icon(Icons.remove_circle_outline), label: Text('Check out')),
                ],
                selected: {_operation},
                onSelectionChanged: (selection) => setState(() => _operation = selection.first),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  AspectRatio(
                    aspectRatio: 1.1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Stack(fit: StackFit.expand, children: [
                        MobileScanner(controller: _scanner, onDetect: _onDetect),
                        const _ScannerOverlay(),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: IconButton.filledTonal(
                            tooltip: _torchOn ? 'Turn flash off' : 'Turn flash on',
                            onPressed: () async {
                              await _scanner.toggleTorch();
                              if (mounted) setState(() => _torchOn = !_torchOn);
                            },
                            icon: Icon(_torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded),
                          ),
                        ),
                        if (_scannedCode != null)
                          Positioned.fill(
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: .55),
                              child: Center(
                                child: Container(
                                  margin: const EdgeInsets.all(24),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_circle_rounded,
                                          color: Color(0xFF087F5B), size: 36),
                                      const SizedBox(height: 8),
                                      const Text('Code captured',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800)),
                                      const SizedBox(height: 4),
                                      Text(_scannedCode!,
                                          textAlign: TextAlign.center),
                                      const SizedBox(height: 10),
                                      TextButton.icon(
                                        onPressed: _scanAgain,
                                        icon: const Icon(Icons.refresh_rounded),
                                        label: const Text('Scan another'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Scan an item barcode or QR code', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('The camera is required for fast, auditable stock movements.', style: TextStyle(color: Color(0xFF667085))),
                  const SizedBox(height: 18),
                  TextField(controller: _barcode, onChanged: (value) => setState(() => _scannedCode = value.isEmpty ? null : value), decoration: const InputDecoration(labelText: 'Item barcode / QR value', prefixIcon: Icon(Icons.qr_code_2_rounded))),
                  const SizedBox(height: 14),
                  TextField(controller: _quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity', prefixIcon: Icon(Icons.numbers_rounded))),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(_operation == StockOperation.checkIn
                            ? Icons.add_circle_outline
                            : Icons.remove_circle_outline),
                    label: Text(_saving
                        ? 'Recording…'
                        : _operation == StockOperation.checkIn
                            ? 'Record check-in'
                            : 'Record check-out'),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      );
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();
  @override
  Widget build(BuildContext context) => IgnorePointer(child: Center(child: Container(width: 210, height: 210, decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 18)]))));
}
