import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/methods.dart';

import 'network_api_host.dart';
import 'network_cdn_host.dart';

const _propertyName = "auto_best_host";

/// 启动时是否自动测速并切到延迟最低的网站源 / 图片源
late bool autoBestHost = true;

Future<void> initAutoBestHost() async {
  try {
    final v = await methods.loadProperty(_propertyName);
    autoBestHost = v != "0";
  } catch (_) {
    autoBestHost = true;
  }
}

Future<void> setAutoBestHost(bool value) async {
  autoBestHost = value;
  try {
    await methods.saveProperty(_propertyName, value ? "1" : "0");
  } catch (_) {}
}

/// 后台测速 API 与 CDN, 切到最快的源 (不阻塞启动)
Future<void> autoSelectBestHosts() async {
  if (!autoBestHost) {
    return;
  }
  await Future.wait([
    autoSelectBestApiHost(),
    autoSelectBestCdnHost(),
  ]);
}

/// 设置页开关
Widget autoBestHostSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return SwitchListTile(
        title: const Text("自动选择最快线路"),
        subtitle: const Text("启动时测速 API 分流与图片分流, 自动切到延迟最低的源"),
        value: autoBestHost,
        onChanged: (bool value) async {
          await setAutoBestHost(value);
          setState(() {});
          if (value) {
            defaultToast(context, "已开启, 正在后台测速");
            autoSelectBestHosts();
          }
        },
      );
    },
  );
}
