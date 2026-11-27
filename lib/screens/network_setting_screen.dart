import 'package:flutter/material.dart';
// [patch] 分流实现已合并到 network_shunts.dart
import 'package:jasmine/configs/network_shunts.dart';
import 'package:jasmine/configs/proxy.dart';
import 'package:jasmine/screens/init_screen.dart';

import 'components/right_click_pop.dart';
import 'downloads_screen.dart';

class NetworkSettingScreen extends StatelessWidget {
  const NetworkSettingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("网络设置"),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (BuildContext context) {
                  return const DownloadsScreen();
                }),
              );
            },
            icon: const Icon(Icons.download),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (BuildContext context) {
                  return const InitScreen();
                }),
              );
            },
            icon: const Icon(Icons.save),
          ),
        ],
      ),
      body: ListView(
        children: [
          apiHostSetting(),
          cdnHostSetting(),
          // [patch] 对齐上游: 支持从服务端一键刷新 API / 图片分流
          updateShuntsSetting(),
          proxySetting(),
        ],
      ),
    );
  }
}
