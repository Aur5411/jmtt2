/// 显示模式, 仅安卓有效

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/android_version.dart';

import '../basic/commons.dart';

const _propertyName = "androidDisplayMode";
List<String> _modes = [];
String _androidDisplayMode = "";

Future initAndroidDisplayMode() async {
  if (Platform.isAndroid) {
    _androidDisplayMode = await methods.loadProperty(_propertyName);
    _modes = await methods.loadAndroidModes();
    // [patch] 默认使用设备支持的最高刷新率(如 120Hz)
    // 仅在用户从未手动设置过时生效, 用户选过则一律以用户的为准
    if (_androidDisplayMode.trim().isEmpty && _modes.isNotEmpty) {
      final best = _pickHighestMode(_modes);
      if (best.isNotEmpty) {
        _androidDisplayMode = best;
        await methods.saveProperty(_propertyName, best);
      }
    }
    await _changeMode();
  }
}

/// 从模式列表中挑刷新率最高的一个 (兼容 "120.0" / "120Hz" 等写法)
String _pickHighestMode(List<String> modes) {
  var bestRate = -1.0;
  var best = "";
  for (final m in modes) {
    final rate = double.tryParse(m.trim().replaceAll(RegExp(r'[^0-9.]'), ''));
    if (rate == null) {
      continue;
    }
    if (rate > bestRate) {
      bestRate = rate;
      best = m;
    }
  }
  return best;
}

Future _changeMode() async {
  await methods.setAndroidMode(_androidDisplayMode);
}

Future<void> _chooseAndroidDisplayMode(BuildContext context) async {
  if (Platform.isAndroid) {
    List<String> list = [""];
    list.addAll(_modes);
    String? result = await chooseListDialog<String>(
      context,
      title: "安卓屏幕刷新率",
      values: list,
    );
    if (result != null) {
      await methods.saveProperty(_propertyName, result);
      _androidDisplayMode = result;
      await _changeMode();
    }
  }
}

Widget androidDisplayModeSetting() {
  if (Platform.isAndroid && androidVersion >= 23) {
    return StatefulBuilder(
      builder: (BuildContext context, void Function(void Function()) setState) {
        return ListTile(
          title: const Text("屏幕刷新率(安卓)"),
          subtitle: Text(_androidDisplayMode),
          onTap: () async {
            await _chooseAndroidDisplayMode(context);
            setState(() {});
          },
        );
      },
    );
  }
  return Container();
}
