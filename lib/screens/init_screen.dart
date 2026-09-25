import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/log.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/configs.dart';
import 'package:jasmine/configs/login.dart';

import '../basic/web_dav_sync.dart';
import '../configs/passed.dart';
import 'app_screen.dart';
import 'first_login_screen.dart';
import 'network_setting_screen.dart';

class InitScreen extends StatefulWidget {
  const InitScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _InitScreenState();
}

class _InitScreenState extends State<InitScreen> {
  String? _startupImagePath;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _startupImagePath != null && _startupImagePath!.isNotEmpty
          ? Center(
              child: Image.file(
                File(_startupImagePath!),
                fit: BoxFit.contain,
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
              ),
            )
          : const Center(
              child: Text("initializing..."),
            ),
    );
  }

  Future _init() async {
    try {
      await methods.init();
      final startupImagePath = await methods.getStartupImagePath();
      if (mounted) {
        setState(() {
          _startupImagePath = startupImagePath;
        });
      }
      await methods.init2();
      await initConfigs(context);
      debugPrient("STATE : ${loginStatus}");
      // [patch] 去除开屏隐私锁: 直接标记为已通过, 不再进入解锁浏览器/身份验证界面
      await firstPassed();
      if (loginStatus == LoginStatus.notSet) {
        Future.delayed(Duration.zero, () async {
          await webDavSyncAuto(context);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (BuildContext context) {
              return firstLoginScreen;
            }),
          );
        });
      } else {
        Future.delayed(Duration.zero, () async {
          await webDavSyncAuto(context);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (BuildContext context) {
              return const AppScreen();
            }),
          );
        });
      }
    } catch (e, st) {
      debugPrient("$e\n$st");
      defaultToast(context, "初始化失败, 请设置网络");
      Future.delayed(Duration.zero, () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (BuildContext context) {
            return const NetworkSettingScreen();
          }),
        );
      });
    }
  }
}
