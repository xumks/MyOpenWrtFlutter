import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwrtapp/ui/theme.dart';
import 'package:openwrtapp/ui/widgets/dialogs.dart';

void main() {
  testWidgets('固定 IP 弹窗保存后关闭不触发异常', (tester) async {
    String? saved;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  saved = await showTextInputDialog(
                    context,
                    title: '固定 IP',
                    message: '为设备设置静态租约',
                    hintText: '例如 192.168.1.100',
                    initialValue: '192.168.1.100',
                    validator: (v) => v.isEmpty ? '请输入 IP 地址' : null,
                  );
                },
                child: const Text('fix'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('fix'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('固定 IP'), findsOneWidget);
    expect(find.widgetWithText(TextField, '192.168.1.100'), findsOneWidget);

    await tester.tap(find.text('保存'));
    // 逐帧推进关闭动画，旧实现在这里会因控制器被提前释放而报错
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, '192.168.1.100');
    expect(find.text('固定 IP'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('固定 IP 弹窗校验失败时不关闭', (tester) async {
    String? saved;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  saved = await showTextInputDialog(
                    context,
                    title: '固定 IP',
                    initialValue: '',
                    validator: (v) => v.isEmpty ? '请输入 IP 地址' : null,
                  );
                },
                child: const Text('fix'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('fix'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('请输入 IP 地址'), findsOneWidget);
    expect(find.text('固定 IP'), findsOneWidget);
    expect(saved, isNull);
    expect(tester.takeException(), isNull);
  });
}
