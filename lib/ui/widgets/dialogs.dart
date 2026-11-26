import 'package:flutter/material.dart';

import '../theme.dart';

/// 通用确认对话框。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '确定',
  String cancelText = '取消',
  bool danger = false,
}) async {
  final dark = AppTheme.isDark(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: dark ? const Color(0xFF161E30) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: Text(message, style: const TextStyle(fontSize: 14, height: 1.55)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelText),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: danger ? const Color(0xFFD64545) : AppTheme.primary,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 单条文本输入对话框（用于固定 IP、订阅地址等）。
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? hintText,
  String initialValue = '',
  String confirmText = '保存',
  String? Function(String value)? validator,
  TextInputType keyboardType = TextInputType.text,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextInputDialog(
      title: title,
      message: message,
      hintText: hintText,
      initialValue: initialValue,
      confirmText: confirmText,
      validator: validator,
      keyboardType: keyboardType,
    ),
  );
}

/// 输入对话框由自身持有控制器，避免弹窗关闭动画期间控制器已被释放导致红屏。
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.message,
    required this.hintText,
    required this.initialValue,
    required this.confirmText,
    required this.validator,
    required this.keyboardType,
  });

  final String title;
  final String? message;
  final String? hintText;
  final String initialValue;
  final String confirmText;
  final String? Function(String value)? validator;
  final TextInputType keyboardType;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final error = widget.validator?.call(value);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark(context);
    return AlertDialog(
      backgroundColor: dark ? const Color(0xFF161E30) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(widget.title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null) ...[
            Text(widget.message!,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppTheme.textSecondary(context),
                )),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: widget.keyboardType,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: widget.hintText,
              errorText: _errorText,
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
