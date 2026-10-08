import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mconnect/core/theme/app_colors.dart';
import '../../../../core/theme/platform_accent.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../models/platform_type.dart';
import '../../../../platform/base/music_platform.dart';
import '../providers/auth_provider.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/widgets/async_state_view.dart';

class LoginPage extends ConsumerStatefulWidget {
  final PlatformType platform;

  const LoginPage({super.key, required this.platform});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  QrLoginResult? _qrResult;
  QrLoginStatus _status = QrLoginStatus.waiting;
  bool _loading = true;
  String? _error;
  StreamSubscription<QrLoginStatus>? _pollSubscription;
  String _kugouAuthVariant = 'lite';

  String? get _authVariant =>
      widget.platform == PlatformType.kugou ? _kugouAuthVariant : null;

  @override
  void initState() {
    super.initState();
    _initLogin();
  }

  @override
  void dispose() {
    _pollSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initLogin() async {
    try {
      final qrResult = await ref
          .read(authProvider.notifier)
          .getQrCodeWithVariant(widget.platform, authVariant: _authVariant);
      if (!mounted) return;
      setState(() {
        _qrResult = qrResult;
        _loading = false;
        _error = null;
      });
      _startPolling(qrResult.key);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '获取二维码失败: $e';
        _loading = false;
      });
    }
  }

  void _startPolling(String key) {
    _pollSubscription?.cancel();
    _pollSubscription = ref
        .read(authProvider.notifier)
        .pollQrStatus(widget.platform, key, authVariant: _authVariant)
        .listen((status) async {
          if (!mounted) return;
          setState(() => _status = status);
          if (status == QrLoginStatus.success) {
            await ref
                .read(authProvider.notifier)
                .onQrLoginSuccess(widget.platform);
            if (!mounted) return;
            showSuccessSnackBar(context, '登录成功');
            Navigator.pop(context);
          } else if (status == QrLoginStatus.expired) {
            // Allow retry
          }
        });
  }

  Color _platformColor() => PlatformAccent.colorOf(context, widget.platform);

  String _statusText() {
    switch (_status) {
      case QrLoginStatus.waiting:
        return '请使用手机扫描二维码登录';
      case QrLoginStatus.scanned:
        return '已扫码，请在手机上确认登录';
      case QrLoginStatus.success:
        return '登录成功';
      case QrLoginStatus.expired:
        return '二维码已过期，请点击刷新';
      case QrLoginStatus.failed:
        return '登录失败，请重试';
    }
  }

  IconData _statusIcon() {
    switch (_status) {
      case QrLoginStatus.waiting:
        return Icons.qr_code_scanner;
      case QrLoginStatus.scanned:
        return Icons.check_circle_outline;
      case QrLoginStatus.success:
        return Icons.check_circle;
      case QrLoginStatus.expired:
        return Icons.timer_off_outlined;
      case QrLoginStatus.failed:
        return Icons.error_outline;
    }
  }

  void _changeKugouAuthVariant(String variant) {
    if (_kugouAuthVariant == variant) return;
    _pollSubscription?.cancel();
    setState(() {
      _kugouAuthVariant = variant;
      _qrResult = null;
      _status = QrLoginStatus.waiting;
      _loading = true;
      _error = null;
    });
    _initLogin();
  }

  @override
  Widget build(BuildContext context) {
    final platformColor = _platformColor();
    final cs = Theme.of(context).colorScheme;

    // QR-code login is the only login method.
    //
    // Kugou's phone/SMS login was removed in v1.4.1 (user decision): the request
    // carried the phone number in cleartext to a host without usable TLS, and
    // `KugouPlatform.supportsPhoneLogin` now reports `false`. Netease's phone
    // entry point was already gone before that, so nothing here offers it — the
    // platform layer still *declares* `sendPhoneCode`/`loginByPhone` (the
    // interface cannot drop them) but every implementation that had them is
    // either refused or gone.
    final supportsQrLogin =
        widget.platform == PlatformType.netease ||
        widget.platform == PlatformType.qq ||
        widget.platform == PlatformType.kugou;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.platform.displayName}登录')),
      body: _loading
          ? const AsyncStateView.loading()
          : _error != null
          ? AsyncStateView.error(
              title: _error!,
              onRetry: () {
                setState(() {
                  _error = null;
                  _loading = true;
                });
                _initLogin();
              },
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  if (widget.platform == PlatformType.kugou) ...[
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'lite',
                          label: Text('酷狗概念版'),
                          icon: Icon(Icons.workspace_premium_outlined),
                        ),
                        ButtonSegment(
                          value: 'android',
                          label: Text('酷狗音乐'),
                          icon: Icon(Icons.music_note_outlined),
                        ),
                      ],
                      selected: {_kugouAuthVariant},
                      onSelectionChanged: (selection) =>
                          _changeKugouAuthVariant(selection.first),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (supportsQrLogin) ...[
                    // QR Code display
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: _qrResult?.qrBytes != null
                          ? Image.memory(
                              Uint8List.fromList(_qrResult!.qrBytes!),
                              width: 200,
                              height: 200,
                            )
                          : _qrResult?.qrUrl != null
                          ? QrImageView(
                              data: _qrResult!.qrUrl!,
                              size: 200,
                              backgroundColor: AppColors.qrBackground,
                            )
                          : Container(
                              width: 200,
                              height: 200,
                              color: cs.surfaceContainerHighest,
                              child: const Icon(Icons.qr_code, size: 64),
                            ),
                    ),
                    const SizedBox(height: 20),
                    // Status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_statusIcon(), size: 20, color: platformColor),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _statusText(),
                            style: TextStyle(
                              color: _status == QrLoginStatus.expired
                                  ? cs.error
                                  : cs.onSurface,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_status == QrLoginStatus.expired)
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _status = QrLoginStatus.waiting;
                          });
                          _initLogin();
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('刷新二维码'),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
