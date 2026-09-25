import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/log.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/login.dart';

enum DailySignStatus {
  unchecked,
  checking,
  signed,
  error,
}

DailySignStatus dailySignStatus = DailySignStatus.unchecked;

final dailySignEvent = Event();

void _setDailySignStatus(DailySignStatus status) {
  dailySignStatus = status;
  dailySignEvent.broadcast();
}

String dailySignStatusLabel() {
  switch (dailySignStatus) {
    case DailySignStatus.checking:
      return "检测中...";
    case DailySignStatus.signed:
      return "已打卡";
    case DailySignStatus.error:
      return "打卡失败";
    case DailySignStatus.unchecked:
    default:
      return "未检测打卡";
  }
}

Future<void> checkDailySignStatus(BuildContext context,
    {bool toast = false}) async {
  if (loginStatus != LoginStatus.loginSuccess) {
    _setDailySignStatus(DailySignStatus.unchecked);
    return;
  }
  _setDailySignStatus(DailySignStatus.checking);
  // [patch] 打卡失败自动重试(最多 3 次), 网络抖动不再直接判定失败
  Object? lastError;
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final msg = await methods
          .daily(selfInfo.uid)
          .timeout(const Duration(seconds: 20));
      if (toast) {
        defaultToast(context, msg.isNotEmpty ? msg : "已打卡");
      }
      _setDailySignStatus(DailySignStatus.signed);
      return;
    } catch (e, st) {
      debugPrient("$e\n$st");
      lastError = e;
      if (attempt < 2) {
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
  }
  if (toast) {
    defaultToast(context, "$lastError");
  }
  _setDailySignStatus(DailySignStatus.error);
}
