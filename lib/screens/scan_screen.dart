import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';

import '../services/ocr_service.dart';
import '../config/theme.dart';
import '../config/routes.dart';
import '../providers/scan_provider.dart';
import '../models/scan_record.dart';
import '../main.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with TickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  bool _isFlashOn = false;
  String? _cameraError;

  // ─── Auto-scan state ──────────────────────────────────
  Timer? _autoScanTimer;
  String? _trackedVehicle; // plate currently being monitored
  int _emptyCount = 0; // consecutive scans with no plate
  String _scanStatus = 'Initializing...';
  static const int _emptyThreshold = 1; // 1 empty scan (3 seconds) unlocks it
  static const Duration _scanInterval = Duration(seconds: 3);

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No cameras found on this device');
        return;
      }

      // Use the back camera
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      // Set autofocus and auto exposure for best image quality
      try {
        await _cameraController!.setFocusMode(FocusMode.auto);
        await _cameraController!.setExposureMode(ExposureMode.auto);
      } catch (e) {
        debugPrint('Focus/Exposure mode error: $e');
      }

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _scanStatus = 'Scanning... — idle, looking for plates';
        });
        // Start auto-scanning
        _startAutoScan();
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) {
        setState(() => _cameraError = 'Camera initialization failed');
      }
    }
  }

  void _startAutoScan() {
    _autoScanTimer?.cancel();
    _autoScanTimer = Timer.periodic(_scanInterval, (_) => _autoCapture());
  }

  void _stopAutoScan() {
    _autoScanTimer?.cancel();
    _autoScanTimer = null;
  }

  @override
  void dispose() {
    _stopAutoScan();
    _cameraController?.dispose();
    _pulseController.dispose();
    _glowController.dispose();
    super.dispose();
  }



  Future<void> _autoCapture() async {
    if (_isCapturing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }
    _isCapturing = true;

    try {
      final XFile image = await _cameraController!.takePicture();

      // Run OCR
      String vehicleNo = '';
      try {
        vehicleNo = await OcrService.recognizeVehicleNo(image.path);
      } catch (e) {
        debugPrint('OCR error: $e');
      }

      if (!mounted) return;

      final trimmedNo = vehicleNo.trim();

      if (trimmedNo.isNotEmpty) {
        // ─── Plate detected (Truck is physically present) ───
        _emptyCount = 0; // reset empty counter

        if (_trackedVehicle == null) {
          // A brand new truck just arrived in the camera frame!
          // 1. Instantly send it to the web application so it updates on detection (Arrival)
          _sendScanAndNotify(trimmedNo);

          // 2. Put on Camera Blinds to ignore everything else while it's parked
          _trackedVehicle = trimmedNo; // Retain the plate in memory!
          
          setState(() => _scanStatus = 'Monitoring: $_trackedVehicle — truck detected and being tracked');
          return;
        }

        // ─── Camera Blinds are ON ───
        // We are already locked onto a truck (_trackedVehicle != null).
        // Since the camera is seeing *some* text right now, the physical truck is STILL sitting there.
        // We absolutely IGNORE whatever text the OCR just read (e.g. MH12A81234 glitch).
        // The camera refuses to look at any other plate until the current truck physically drives away!
        setState(() => _scanStatus = 'Monitoring: $_trackedVehicle — truck detected and being tracked');
        return;

      } else {
        // ─── No plate detected (empty space) ────────────
        if (_trackedVehicle != null) {
          _emptyCount++;
          setState(
            () => _scanStatus =
                'Vehicle leaving... ($_emptyCount/$_emptyThreshold) — empty scans counting toward OUT',
          );

          if (_emptyCount >= _emptyThreshold) {
            // Camera saw empty space for a few seconds.
            // The truck has definitively vanished from the frame! 
            
            // 1. Send the retained plate memory to the web application!
            _sendScanAndNotify(_trackedVehicle!);

            // 2. Unlock the scanner completely for the next truck!
            setState(() {
              _trackedVehicle = null;
              _emptyCount = 0;
              _scanStatus = 'Scanning... — idle, looking for plates';
            });
          }
        } else {
          // No tracked vehicle, just idle scanning
          if (mounted) {
            setState(() => _scanStatus = 'Scanning... — idle, looking for plates');
          }
        }
      }
    } catch (e) {
      debugPrint('Auto-capture error: $e');
    } finally {
      _isCapturing = false;
    }
  }

  /// Sends the tracked vehicle to the server and handles the UI popup
  Future<void> _sendScanAndNotify(String vehicleNo) async {
    if (!mounted) return;
    final provider = context.read<ScanProvider>();
    
    // We update the UI so the guard knows we are sending it
    setState(() => _scanStatus = 'Sending: $vehicleNo...');

    final response = await provider.scanVehicle(vehicleNo);
    if (!mounted) return;

    if (response.success) {
      if (response.action == 'ARRIVAL') {
        setState(() => _scanStatus = 'IN: $vehicleNo');
        _showSuccessSnackbar(
          Icons.login_rounded,
          'Gate In Success ✅  $vehicleNo',
          AppTheme.successColor,
        );
      } else if (response.action == 'DEPARTURE') {
        setState(() => _scanStatus = 'OUT: $vehicleNo');
        _showSuccessSnackbar(
          Icons.logout_rounded,
          'Gate Out Success ✅  $vehicleNo',
          Colors.deepOrange,
        );
      } else {
        // THIS IS THE DEBUG BRANCH!
        // If the server returned 200 OK, but action wasn't ARRIVAL or DEPARTURE
        setState(() => _scanStatus = 'Unknown Action: "${response.action}"');
        _showErrorSnackbar(
          'API ERROR: Server replied with Success, but action was: "${response.action}". It MUST be exactly "DEPARTURE" to work!',
        );
      }
    } else {
      // Server rejected or network error
      setState(() => _scanStatus = 'Error: $vehicleNo');
      _showErrorSnackbar(
        response.error ?? 'Failed to process scan for $vehicleNo',
      );
    }
  }

  void _showSuccessSnackbar(IconData icon, String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppTheme.errorColor.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scannerBg,
      body: Stack(
        children: [
          // Live camera preview or fallback
          _buildCameraPreview(),

          // Dark overlay at top and bottom for controls readability
          _buildGradientOverlays(),

          // Last scan result card
          _buildResultCard(),

          // Top controls
          _buildTopControls(),

          // Bottom controls
          _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_cameraError != null) {
      return Container(
        color: AppTheme.scannerBg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.videocam_off_rounded,
                color: Colors.white.withValues(alpha: 0.3),
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                _cameraError!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _initCamera,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isCameraInitialized || _cameraController == null) {
      return Container(
        color: AppTheme.scannerBg,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppTheme.primaryColor),
              SizedBox(height: 16),
              Text(
                'Starting camera...',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // Full-screen camera preview
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _cameraController!.value.previewSize!.height,
          height: _cameraController!.value.previewSize!.width,
          child: CameraPreview(_cameraController!),
        ),
      ),
    );
  }

  Widget _buildGradientOverlays() {
    return Column(
      children: [
        // Top gradient for status bar + controls
        Container(
          height: MediaQuery.of(context).padding.top + 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
            ),
          ),
        ),
        const Spacer(),
        // Bottom gradient for controls
        Container(
          height: 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard() {
    return Consumer<ScanProvider>(
      builder: (context, provider, _) {
        if (provider.entries.isEmpty) return const SizedBox.shrink();

        final lastEntry = provider.entries.first;

        return Positioned(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).padding.bottom + 140,
          child: GestureDetector(
            onTap: () {
              Navigator.pushNamed(
                context,
                AppRoutes.recordDetail,
                arguments: lastEntry.id,
              );
            },
            child: _GlassCard(entry: lastEntry),
          ),
        );
      },
    );
  }

  Widget _buildTopControls() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 20,
      right: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ShaderMask(
            shaderCallback: (bounds) =>
                AppTheme.primaryGradient.createShader(bounds),
            child: const Text(
              'TKAP',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ),
          Row(
            children: [
              if (_isCameraInitialized)
                _CircleButton(
                  icon: _isFlashOn
                      ? Icons.flash_on_rounded
                      : Icons.flash_off_rounded,
                  onTap: () async {
                    if (_cameraController == null) return;
                    try {
                      if (_isFlashOn) {
                        await _cameraController!.setFlashMode(FlashMode.off);
                      } else {
                        await _cameraController!.setFlashMode(FlashMode.torch);
                      }
                      setState(() => _isFlashOn = !_isFlashOn);
                    } catch (e) {
                      debugPrint('Flash error: $e');
                    }
                  },
                ),
              const SizedBox(width: 8),
              _CircleButton(
                icon: Icons.grid_view_rounded,
                onTap: () {
                  final appShellState = context
                      .findAncestorStateOfType<AppShellState>();
                  appShellState?.switchToTab(1);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    // Determine status color
    Color statusColor;
    IconData statusIcon;
    if (_trackedVehicle != null && _emptyCount > 0) {
      statusColor = Colors.deepOrange;
      statusIcon = Icons.logout_rounded;
    } else if (_trackedVehicle != null) {
      statusColor = Colors.green;
      statusIcon = Icons.local_shipping_rounded;
    } else {
      statusColor = AppTheme.primaryColor;
      statusIcon = Icons.radar_rounded;
    }

    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 32,
      left: 0,
      right: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Live status indicator
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: statusColor.withValues(
                    alpha: _glowAnimation.value * 0.6,
                  ),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(
                      alpha: _glowAnimation.value * 0.2,
                    ),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pulsing dot
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, _) => Container(
                      width: 10 * _pulseAnimation.value,
                      height: 10 * _pulseAnimation.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(statusIcon, color: statusColor, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _scanStatus,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Manual entry button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _BottomAction(
                icon: Icons.edit_note_rounded,
                label: 'Manual',
                onTap: () {
                  Navigator.pushNamed(context, AppRoutes.details);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Glass Card Widget ──────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final TruckEntry entry;
  const _GlassCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.glassBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          color: AppTheme.glassOverlay,
          child: Row(
            children: [
              Container(
                width: 4,
                height: 56,
                decoration: const BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor.withValues(alpha: 0.2),
                      AppTheme.cyan.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  color: AppTheme.primaryLight,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    entry.vehicleNo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // IN/OUT status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: entry.isOut
                      ? Colors.deepOrange.withValues(alpha: 0.25)
                      : Colors.greenAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: entry.isOut
                        ? Colors.deepOrange.withValues(alpha: 0.5)
                        : Colors.greenAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  entry.isOut ? 'OUT' : 'IN',
                  style: TextStyle(
                    color: entry.isOut
                        ? Colors.deepOrange[200]
                        : Colors.greenAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Supporting Widgets ─────────────────────────────────────────────

class _BottomAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Icon(icon, color: Colors.white70, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
    );
  }
}
