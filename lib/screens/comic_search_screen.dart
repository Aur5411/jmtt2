import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/blocked_tags.dart';
import 'package:jasmine/screens/components/floating_search_bar.dart';

import 'components/browser_bottom_sheet.dart';
import 'components/comic_floating_search_bar.dart';
import 'components/comic_pager.dart';
import 'components/actions.dart';
import 'components/right_click_pop.dart';

class ComicSearchScreen extends StatefulWidget {
  final String initKeywords;

  const ComicSearchScreen({required this.initKeywords, Key? key})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _ComicSearchScreenState();
}

class _ComicSearchScreenState extends State<ComicSearchScreen> {
  final _controller = FloatingSearchBarController();
  late var _keywords = widget.initKeywords;
  SortBy _sortBy = sortByDefault;

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  /// 把常驻屏蔽名单拼成 "-词" 附加到搜索串, 交给服务端按 tag 索引排除
  String _queryWithBlockedTags(String input) {
    final extras = <String>[];
    for (final tag in currentBlockedTags()) {
      for (final w in tag.split(RegExp(r'\s+'))) {
        final t = w.trim();
        if (t.isEmpty) {
          continue;
        }
        if (input.contains("-$t")) {
          continue;
        }
        extras.add("-$t");
      }
    }
    if (extras.isEmpty) {
      return input;
    }
    return [input, ...extras].join(' ');
  }

  Widget buildScreen(BuildContext context) {
    return ComicFloatingSearchBarScreen(
      controller: _controller,
      onQuery: (value) {
        setState(() {
          _keywords = value;
        });
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_keywords),
          actions: [
            IconButton(
              onPressed: () async {
                searchHistories = await methods.lastSearchHistories(20);
                _controller.display(modifyInput: _keywords);
              },
              icon: const Icon(Icons.search),
            ),
            const BrowserBottomSheetAction(),
            buildOrderSwitch(context, _sortBy, (value) {
              setState(() {
                _sortBy = value;
              });
            }),
          ],
        ),
        body: ComicPager(
          key: Key("$_keywords:$_sortBy"),
          onPage: (int page) async {
            // [patch] Tag 屏蔽交给服务端:
            // 列表数据只有 8 个字段(无 tags), 本地只能按标题/简介文本匹配, 漏网很多;
            // 把常驻屏蔽名单拼成 "-词" 一起发给服务端, 服务端有 tag 索引, 能真正排除。
            // 若服务端不支持该语法(结果为空), 回落为纯关键词再搜, 本地继续兜底过滤。
            final parsed = parseSearchQuery(_keywords);
            final query = _queryWithBlockedTags(_keywords);
            var response = await methods.comicSearch(
              query,
              _sortBy,
              page,
            );
            if (query != _keywords &&
                !parsed.isKeywordsEmpty &&
                response.content.isEmpty) {
              response = await methods.comicSearch(
                parsed.keywords,
                _sortBy,
                page,
              );
            }
            if (parsed.isKeywordsEmpty && response.content.isEmpty) {
              defaultToast(context, "请输入搜索关键词, \"-xxx\" 只作为排除词");
            }
            // [patch] 本地兜底: 常驻屏蔽 Tag + 本次搜索临时排除词
            final list = response.content
                .where((comic) =>
                    !comicBlockedByTags(comic) &&
                    !comicBlockedByExcludes(comic, parsed.excludes))
                .toList();
            final filtered = response.content.length - list.length;
            if (filtered > 0) {
              defaultToast(
                context,
                parsed.hasExcludes
                    ? "已过滤 $filtered 个结果 (排除词 ${parsed.excludes.join("/")})"
                    : "已按屏蔽 Tag 过滤 $filtered 个结果",
              );
            }
            return InnerComicPage(
              total: response.total,
              list: list,
              redirectAid: response.redirectAid,
            );
          },
        ),
      ),
    );
  }
}
