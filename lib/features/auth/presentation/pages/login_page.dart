import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../models/platform_type.dart';
import '../../../../platform/base/music_platform.dart';
import '../providers/auth_provider.dart';

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
  bool _showPhoneLogin = false;
  String _kugouAuthVariant = 'lite';

  // Phone login fields
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _phoneLoading = false;
  bool _codeLoading = false;

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
    _phoneController.dispose();
    _codeController.dispose();
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
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('登录成功')));
            Navigator.pop(context);
          } else if (status == QrLoginStatus.expired) {
            // Allow retry
          }
        });
  }

  Future<void> _handlePhoneLogin() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    if (phone.isEmpty || code.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入手机号和验证码')));
      return;
    }
    setState(() => _phoneLoading = true);
    final result = await ref
        .read(authProvider.notifier)
        .loginByPhone(widget.platform, phone, code, authVariant: _authVariant);
    if (!mounted) return;
    setState(() => _phoneLoading = false);
    if (result.success) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('登录成功')));
      Navigator.pop(context);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.error ?? '登录失败')));
    }
  }

  Future<void> _handleSendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入手机号')));
      return;
    }
    setState(() => _codeLoading = true);
    final result = await ref
        .read(authProvider.notifier)
        .sendPhoneCode(widget.platform, phone, authVariant: _authVariant);
    if (!mounted) return;
    setState(() => _codeLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.success ? '验证码已发送' : (result.error ?? '验证码发送失败')),
      ),
    );
  }

  Color _platformColor() {
    switch (widget.platform) {
      case PlatformType.local:
        return Theme.of(context).colorScheme.primary;
      case PlatformType.netease:
        return const Color(0xFFE60026);
      case PlatformType.qq:
        return const Color(0xFF31C27C);
      case PlatformType.kugou:
        return const Color(0xFF2CA2F9);
    }
  }

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

    // Phone login is available for Netease and Kugou
    final supportsPhoneLogin =
        widget.platform == PlatformType.netease ||
        widget.platform == PlatformType.kugou;
    // QR login is available for all registered platforms.
    final supportsQrLogin =
        widget.platform == PlatformType.netease ||
        widget.platform == PlatformType.qq ||
        widget.platform == PlatformType.kugou;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.platform.displayName}登录')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: cs.error),
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: cs.error)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _error = null;
                        _loading = true;
                      });
                      _initLogin();
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
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
                              backgroundColor: Colors.white,
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
                  // Phone login toggle
                  if (supportsPhoneLogin) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () =>
                          setState(() => _showPhoneLogin = !_showPhoneLogin),
                      child: Text(
                        _showPhoneLogin ? '收起手机号登录' : '使用手机号登录',
                        style: TextStyle(color: platformColor),
                      ),
                    ),
                    if (_showPhoneLogin) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: '手机号',
                          prefixIcon: const Icon(Icons.phone),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '验证码',
                          prefixIcon: const Icon(Icons.sms),
                          suffixIcon: TextButton(
                            onPressed: _codeLoading ? null : _handleSendCode,
                            child: _codeLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('获取验证码'),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _phoneLoading ? null : _handlePhoneLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: platformColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _phoneLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('登录'),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}
