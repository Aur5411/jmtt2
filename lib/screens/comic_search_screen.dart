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
            // [patch] 支持 "-关键词" 排除语法: 剥离排除词后再请求, 结果本地剔除
            final parsed = parseSearchQuery(_keywords);
            if (parsed.isKeywordsEmpty) {
              if (parsed.hasExcludes) {
                defaultToast(context, "请输入搜索关键词, \"-xxx\" 只作为排除词");
              }
              return InnerComicPage(
                total: 0,
                list: <ComicSimple>[],
              );
            }
            final response = await methods.comicSearch(
              parsed.keywords,
              _sortBy,
              page,
            );
            // [patch] 屏蔽过滤: 常驻屏蔽 Tag + 本次搜索临时排除词
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
                    ? "已过滤 $filtered 个结果 (屏蔽 Tag + 排除词 ${parsed.excludes.join("/")})"
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
