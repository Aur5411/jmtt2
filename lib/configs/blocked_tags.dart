import 'dart:convert';

import 'package:flutter/material.dart';

import '../basic/commons.dart';
import '../basic/entities.dart';
import '../basic/methods.dart';

const _propertyName = "blocked_tags";

/// 屏蔽 Tag 列表, 搜索/列表加载时自动过滤命中内容
List<String> _blockedTags = [];

Future<void> initBlockedTags() async {
  final str = await methods.loadProperty(_propertyName);
  if (str.isEmpty) {
    _blockedTags = [];
    return;
  }
  try {
    final decoded = jsonDecode(str);
    if (decoded is List) {
      _blockedTags = decoded
          .map((e) => "$e".trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
  } catch (_) {
    _blockedTags = [];
  }
}

List<String> currentBlockedTags() {
  return List.unmodifiable(_blockedTags);
}

bool isTagBlocked(String tag) {
  return _blockedTags.contains(tag.trim());
}

Future<void> addBlockedTag(String tag) async {
  tag = tag.trim();
  if (tag.isEmpty || _blockedTags.contains(tag)) {
    return;
  }
  _blockedTags.add(tag);
  await methods.saveProperty(_propertyName, jsonEncode(_blockedTags));
}

Future<void> removeBlockedTag(String tag) async {
  tag = tag.trim();
  if (!_blockedTags.contains(tag)) {
    return;
  }
  _blockedTags.remove(tag);
  await methods.saveProperty(_propertyName, jsonEncode(_blockedTags));
}

/// 判断一个漫画是否命中屏蔽词 (匹配 名称/作者/简介/分类标题/子分类标题, 忽略大小写)
bool comicBlockedByTags(ComicBasic comic) {
  if (_blockedTags.isEmpty) {
    return false;
  }
  final fields = [
    comic.name.toLowerCase(),
    comic.author.toLowerCase(),
    comic.description.toLowerCase(),
    comic.category?.title ?? "",
    comic.categorySub?.title ?? "",
  ];
  for (final blocked in _blockedTags) {
    final tag = blocked.trim().toLowerCase();
    if (tag.isEmpty) {
      continue;
    }
    for (final field in fields) {
      if (field.contains(tag)) {
        return true;
      }
    }
  }
  return false;
}

/// 设置页入口: 屏蔽 Tag 管理
Widget blockedTagsSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        leading: const Icon(Icons.block),
        title: const Text("屏蔽 Tag 设置"),
        subtitle: Text(
          _blockedTags.isEmpty
              ? "未屏蔽任何 Tag (搜索/列表自动隐藏命中内容)"
              : "已屏蔽 ${_blockedTags.length} 个: ${_blockedTags.take(5).join(" / ")}${_blockedTags.length > 5 ? " ..." : ""}",
        ),
        onTap: () async {
          await _manageBlockedTags(context);
          setState(() {});
        },
      );
    },
  );
}

Future<void> _manageBlockedTags(BuildContext context) async {
  while (true) {
    final action = await chooseListDialog<String>(
      context,
      title: "屏蔽 Tag 管理 (当前 ${_blockedTags.length} 个)",
      values: [..._blockedTags, "添加新 Tag", "完成"],
      tips: "选择某个 Tag 将其移除屏蔽; 选择 \"添加新 Tag\" 新增屏蔽项。",
    );
    if (action == null || action == "完成") {
      return;
    }
    if (action == "添加新 Tag") {
      final tag = await displayTextInputDialog(
        context,
        title: "添加屏蔽 Tag",
        hint: "输入 Tag 关键字 (匹配名称/作者/分类)",
      );
      if (tag != null && tag.trim().isNotEmpty) {
        await addBlockedTag(tag);
        defaultToast(context, "已屏蔽 Tag: ${tag.trim()}");
      }
      continue;
    }
    // 选中已有 Tag -> 确认移除
    final target = action;
    final confirm = await confirmDialog(context, "移除屏蔽", "不再屏蔽 Tag \"$target\"?");
    if (confirm) {
      await removeBlockedTag(target);
      defaultToast(context, "已取消屏蔽: $target");
    }
  }
}
