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

  /// [patch] 搜索序号: 原来 ComicPager 的 Key 只由关键词+排序拼成,
  /// 用同一个关键词再搜一次(例如刚改了屏蔽 Tag、或上次结果异常想重试)
  /// Key 不变 -> pager 状态被复用 -> 根本不重新请求, 表现为「搜索没反应」。
  /// 每次提交都自增, 保证一定重建并重新拉取。
  int _searchSeq = 0;

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
          // [patch] 同一关键词重复提交时也强制重建 pager, 保证真的重发请求
          _searchSeq++;
        });
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_keywords),
          actions: [
            IconButton(
              onPressed: () async {
                // [patch] 历史接口偶发失败时不再让磁贴点击毫无反应:
                // 失败就当没有历史, 面板照常弹出(板块标签仍可用)
                try {
                  searchHistories = await methods.lastSearchHistories(20);
                } catch (e) {
                  searchHistories = const [];
                  if (mounted) {
                    defaultToast(context, "搜索历史加载失败: $e");
                  }
                }
                if (!mounted) {
                  return;
                }
                _controller.display(modifyInput: _keywords);
              },
              icon: const Icon(Icons.search),
            ),
            const BrowserBottomSheetAction(),
            buildOrderSwitch(context, _sortBy, (value) {
              setState(() {
                _sortBy = value;
                // [patch] 排序切换也走自增, 避免同 Key 复用旧列表
                _searchSeq++;
              });
            }),
          ],
        ),
        body: ComicPager(
          key: Key("$_keywords:$_sortBy:$_searchSeq"),
          onPage: (int page) async {
            // [patch] Tag 屏蔽交给服务端:
            // 列表数据只有 8 个字段(无 tags), 本地只能按标题/简介文本匹配, 漏网很多;
            // 把常驻屏蔽名单拼成 "-词" 一起发给服务端, 服务端有 tag 索引, 能真正排除。
            // 若服务端不支持该语法(结果为空), 回落为纯关键词再搜, 本地继续兜底过滤。
            final parsed = parseSearchQuery(_keywords);
            final query = _queryWithBlockedTags(_keywords);
            ComicsResponse response;
            try {
              response = await methods.comicSearch(
                query,
                _sortBy,
                page,
              );
              // [patch] 回落条件放宽: 原来要求「有关键词」才回落, 纯排除词搜索
              // (只输入 "-xxx") 首请求为空时直接给空页; 现在只要拼了屏蔽词且
              // 结果为空就回落到原始输入重搜一次
              if (query != _keywords && response.content.isEmpty) {
                response = await methods.comicSearch(
                  _keywords,
                  _sortBy,
                  page,
                );
              }
            } catch (e) {
              // [patch] 搜索失败给出可读原因(原来的裸异常只会显示
              // 「出错, 点击重试」, 用户不知道是断网还是被限流)
              throw StateError("搜索失败: $e");
            }
            final isEmpty = response.content.isEmpty;
            // [patch] 提示只在第一页弹, 原来每次翻页都弹一次, 滚动时连续弹窗
            if (page == 1 && parsed.isKeywordsEmpty && isEmpty && mounted) {
              defaultToast(context, "请输入搜索关键词, \"-xxx\" 只作为排除词");
            }
            // [patch] 本地兜底: 常驻屏蔽 Tag + 本次搜索临时排除词
            final list = response.content
                .where((comic) =>
                    !comicBlockedByTags(comic) &&
                    !comicBlockedByExcludes(comic, parsed.excludes))
                .toList();
            final filtered = response.content.length - list.length;
            if (page == 1 && filtered > 0 && mounted) {
              defaultToast(
                context,
                parsed.hasExcludes
                    ? "已过滤 $filtered 个结果 (排除词 ${parsed.excludes.join("/")})"
                    : "已按屏蔽 Tag 过滤 $filtered 个结果",
              );
            }
            // [patch] total 扣掉本地过滤数: 原来直接用服务端 total, 被屏蔽的
            // 条目仍计入总数, 导致页数偏多、后几页翻出空页
            final total = response.total - filtered;
            return InnerComicPage(
              total: total < 0 ? 0 : total,
              list: list,
              redirectAid: response.redirectAid,
            );
          },
        ),
      ),
    );
  }
}
