import 'package:flutter/material.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';

const _propertyName = "reader_preload_count";
const _concurrencyName = "reader_preload_concurrency";

/// 进入章节时向后预缓存的页数 (0 = 整章)
late int readerPreloadCount = 12;

/// 预缓存并发数 (同时下载多少页)
late int readerPreloadConcurrency = 12;

Future<void> initReaderPreloadCount() async {
  try {
    final v = await methods.loadProperty(_propertyName);
    if (v.isNotEmpty) {
      readerPreloadCount = int.tryParse(v) ?? 12;
      // [patch] v2.10 曾默认整章(0), 现按需求回落为 12 页并写回, 避免旧值残留
      if (readerPreloadCount == 0) {
        readerPreloadCount = 12;
        await methods.saveProperty(_propertyName, "12");
      }
    }
    final c = await methods.loadProperty(_concurrencyName);
    if (c.isNotEmpty) {
      final parsed = int.tryParse(c) ?? 12;
      readerPreloadConcurrency = parsed.clamp(1, 32);
    } else {
      readerPreloadConcurrency = 12;
    }
  } catch (_) {
    readerPreloadCount = 12;
    readerPreloadConcurrency = 12;
  }
}

Future<void> setReaderPreloadCount(int value) async {
  readerPreloadCount = value;
  try {
    await methods.saveProperty(_propertyName, "$value");
  } catch (_) {}
}

String readerPreloadCountLabel() {
  return readerPreloadCount <= 0 ? "整章" : "$readerPreloadCount 页";
}

/// 设置页入口
Widget readerPreloadCountSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        leading: const Icon(Icons.downloading_outlined),
        title: const Text("阅读预缓存页数"),
        subtitle: Text(
          "当前: ${readerPreloadCountLabel()} (进入章节即后台缓存, 翻页不再等待)",
        ),
        onTap: () async {
          final choose = await chooseListDialog<String>(
            context,
            title: "阅读预缓存页数",
            values: const ["12 页", "30 页", "50 页", "100 页", "整章"],
            tips: "越多翻页越顺, 但占用更多流量与存储",
          );
          if (choose == null) {
            return;
          }
          final value = choose == "整章"
              ? 0
              : int.tryParse(choose.replaceAll(" 页", "")) ?? 0;
          await setReaderPreloadCount(value);
          setState(() {});
          defaultToast(context, "已设置为 ${readerPreloadCountLabel()}");
        },
      );
    },
  );
}

Future<void> setReaderPreloadConcurrency(int value) async {
  readerPreloadConcurrency = value.clamp(1, 32);
  try {
    await methods.saveProperty(_concurrencyName, "$readerPreloadConcurrency");
  } catch (_) {}
}

/// 设置页入口: 预缓存并发数
Widget readerPreloadConcurrencySetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        leading: const Icon(Icons.speed_outlined),
        title: const Text("预缓存并发数"),
        subtitle: Text("当前: $readerPreloadConcurrency (同时下载页数, 越大越快但更吃带宽)"),
        onTap: () async {
          final choose = await chooseListDialog<String>(
            context,
            title: "预缓存并发数",
            values: const ["4", "8", "12", "16", "24", "32"],
          );
          if (choose == null) {
            return;
          }
          final value = int.tryParse(choose) ?? 12;
          await setReaderPreloadConcurrency(value);
          setState(() {});
          defaultToast(context, "已设置为 $readerPreloadConcurrency");
        },
      );
    },
  );
}
