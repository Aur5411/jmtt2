import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:jasmine/basic/comic_seal.dart';

import '../basic/methods.dart';

const _categoryPropertyName = "comicSealCategories";
const _titleWordsPropertyName = "comicSealTitleWords";

Future<void> initComicSealConfig() async {
  final categoryText = await methods.loadProperty(_categoryPropertyName);
  final titleWordsText = await methods.loadProperty(_titleWordsPropertyName);
  updateComicSealRules(
    categories: _parseStringArray(categoryText),
    titleWords: _parseStringArray(titleWordsText),
  );
}

List<String> _parseStringArray(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return <String>[];
  }
  try {
    final decoded = jsonDecode(text);
    if (decoded is List) {
      return decoded
          .map((e) => "$e".trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
  } catch (_) {}
  return <String>[];
}

Future<void> _saveCategories(List<String> values) async {
  await methods.saveProperty(_categoryPropertyName, jsonEncode(values));
  updateComicSealRules(categories: values);
}

Future<void> _saveTitleWords(List<String> values) async {
  await methods.saveProperty(_titleWordsPropertyName, jsonEncode(values));
  updateComicSealRules(titleWords: values);
}

Future<List<String>?> _showStringArrayEditor(
  BuildContext context, {
  required String title,
  required String hintText,
  required List<String> initial,
}) async {
  final controller = TextEditingController(text: initial.join('\n'));
  final result = await showDialog<List<String>>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            minLines: 6,
            maxLines: 12,
            decoration: InputDecoration(
              hintText: hintText,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(<String>[]),
            child: const Text("清空"),
          ),
          FilledButton(
            onPressed: () {
              final lines = controller.text
                  .split('\n')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList(growable: false);
              Navigator.of(context).pop(lines);
            },
            child: const Text("保存"),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}

Widget comicSealCategorySetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      final categories = currentComicSealCategories();
      return ListTile(
        title: const Text("按分类封印"),
        subtitle: Text(
          categories.isEmpty ? "未设置" : categories.join("、"),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () async {
          final result = await _showStringArrayEditor(
            context,
            title: "按分类封印",
            hintText: "每行一个分类名，例如：\n同人\n韩漫",
            initial: categories,
          );
          if (result != null) {
            await _saveCategories(result);
            setState(() {});
          }
        },
      );
    },
  );
}

Widget comicSealTitleWordsSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      final titleWords = currentComicSealTitleWords();
      return ListTile(
        title: const Text("按标题关键字封印"),
        subtitle: Text(
          titleWords.isEmpty ? "未设置" : titleWords.join("、"),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () async {
          final result = await _showStringArrayEditor(
            context,
            title: "按标题关键字封印",
            hintText: "每行一个关键字，例如：\nCloud\n机翻",
            initial: titleWords,
          );
          if (result != null) {
            await _saveTitleWords(result);
            setState(() {});
          }
        },
      );
    },
  );
}
