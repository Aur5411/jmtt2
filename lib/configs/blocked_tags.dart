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

/// 解析后的搜索串
class ParsedSearchQuery {
  /// 剥离排除词后的真实搜索词
  final String keywords;

  /// "-xxx" 提取出的临时排除词
  final List<String> excludes;

  const ParsedSearchQuery(this.keywords, this.excludes);

  bool get hasExcludes => excludes.isNotEmpty;

  bool get isKeywordsEmpty => keywords.trim().isEmpty;
}

/// 解析搜索串: 空格分词, 以 "-" 开头的词视为排除词 (参考官方客户端语法)
/// 例: "全彩 -人妻" -> keywords="全彩", excludes=["人妻"]
ParsedSearchQuery parseSearchQuery(String input) {
  final words = <String>[];
  final excludes = <String>[];
  for (final w in input.split(RegExp(r'\s+'))) {
    if (w.isEmpty) {
      continue;
    }
    if (w.length > 1 && w.startsWith('-')) {
      final tag = w.substring(1).trim().toLowerCase();
      if (tag.isNotEmpty) {
        excludes.add(tag);
      }
    } else {
      words.add(w);
    }
  }
  return ParsedSearchQuery(words.join(' ').trim(), excludes);
}

/// 判断是否命中本次搜索的临时排除词 (匹配 名称/作者/简介/分类/子分类, 忽略大小写)
bool comicBlockedByExcludes(ComicBasic comic, List<String> excludes) {
  if (excludes.isEmpty) {
    return false;
  }
  final fields = [
    comic.name.toLowerCase(),
    comic.author.toLowerCase(),
    comic.description.toLowerCase(),
    (comic.category?.title ?? "").toLowerCase(),
    (comic.categorySub?.title ?? "").toLowerCase(),
  ];
  for (final ex in excludes) {
    for (final field in fields) {
      if (field.contains(ex)) {
        return true;
      }
    }
  }
  return false;
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

/// 设置页入口: 屏蔽 Tag 管理 (醒目卡片, 常驻设置主界面顶部)
Widget blockedTagsSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      final scheme = Theme.of(context).colorScheme;
      final count = _blockedTags.length;
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await _manageBlockedTags(context);
            setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.block,
                    color: scheme.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "屏蔽 Tag 设置",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        count == 0
                            ? "未屏蔽任何 Tag，点击添加"
                            : "已屏蔽 $count 个：${_blockedTags.take(3).join(" / ")}${count > 3 ? " ..." : ""}",
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (count > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "$count",
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
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
