import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/log.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/login.dart';
import 'package:jasmine/screens/components/comic_pager.dart';

import 'components/right_click_pop.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  int _folderId = 0;
  bool _isLoading = true;

  /// [patch] 刷新计数: 改变 ComicPager 的 Key 强制重建, 达到「重新拉第一页」效果
  int _reloadCount = 0;

  final Map<int, String> _folderMap = {
    0: "全部",
  };

  _chooseFolder() async {
    int? f = await chooseMapDialog(
      context,
      values: _folderMap.map((key, value) => MapEntry(value, key)),
      title: "选择文件夹",
    );
    if (f != null) {
      setState(() {
        _folderId = f;
      });
    }
  }

  final _sortNameMap = {
    "mr": "收藏时间",
    "mp": "更新时间",
  };
  String _sort = "mr";

  _chooseSort() async {
    String? f = await chooseMapDialog(
      context,
      values: _sortNameMap.map((key, value) => MapEntry(value, key)),
      title: "选择排序",
    );
    if (f != null) {
      setState(() {
        _sort = f;
      });
      await methods.saveProperty("favorites_sort", f);
    }
  }

  @override
  void initState() {
    super.initState();
    // [patch] 原来在 initState 里直接 defaultToast(context, ...), 既非法
    // (此处 context 还不能用于 Overlay), 也会在解析异常时打断 initState;
    // 现在只静默重建文件夹表, 并主动向服务端拉一次最新文件夹列表
    _rebuildFolderMap();
    _refreshFolders();
    _loadSort();
  }

  /// [patch] 用全局 favData 重建「全部 + 各文件夹」表
  void _rebuildFolderMap() {
    _folderMap.clear();
    _folderMap[0] = "全部";
    for (var value in favData) {
      _folderMap[value.fid] = value.name;
    }
    // [patch] 之前选中的文件夹被删除/改名后下标失效时回落到「全部」
    if (!_folderMap.containsKey(_folderId)) {
      _folderId = 0;
    }
  }

  /// [patch] 进入收藏页时刷新文件夹列表: 原实现只吃 initState 时的内存
  /// favData, fav() 在启动阶段失败一次后就永久只有「全部」, 表现为
  /// 「收藏功能偶尔用不了」(文件夹缺失/选不到)
  Future<void> _refreshFolders() async {
    try {
      await fav(context);
      if (!mounted) {
        return;
      }
      setState(_rebuildFolderMap);
    } catch (e) {
      debugPrient(e);
    }
  }

  /// [patch] 下拉/按钮刷新: 同时刷新文件夹表并重建分页器
  Future<void> _reload() async {
    await _refreshFolders();
    if (!mounted) {
      return;
    }
    setState(() {
      _reloadCount++;
    });
  }

  Future<void> _loadSort() async {
    try {
      final sort = await methods.loadProperty("favorites_sort");
      if (!mounted) {
        return;
      }
      if (sort.isNotEmpty && _sortNameMap.containsKey(sort)) {
        setState(() {
          _sort = sort;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      // 使用默认值
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("收藏夹"),
        actions: [
          MaterialButton(
            onPressed: _chooseSort,
            child: Row(
              children: [
                const Icon(Icons.sort, size: 15),
                Container(width: 8),
                Text(_sortNameMap[_sort] ?? ""),
              ],
            ),
          ),
          MaterialButton(
            onPressed: _chooseFolder,
            child: Row(
              children: [
                const Icon(Icons.folder_copy_outlined, size: 15),
                Container(width: 8),
                Text(_folderMap[_folderId] ?? ""),
              ],
            ),
          ),
          // [patch] 手动刷新入口: 收藏接口失败后用户不必退出重进页面
          IconButton(
            tooltip: "刷新收藏夹",
            onPressed: _reload,
            icon: const Icon(Icons.refresh, size: 18),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ComicPager(
              // [patch] 加入刷新计数, 点刷新时重建 pager 重新拉第一页
              key: Key("FAVOUR:$_folderId:$_sort:$_reloadCount"),
              onPage: (int page) async {
                // [patch] 收藏接口偶发超时/字段漂移时不再把裸异常抛给
                // ComicPager(那样只会显示「出错, 点击重试」且无原因),
                // 这里统一转成可读错误; 失败时保留上一页数据不清空
                try {
                  final response =
                      await methods.favorites(_folderId, page, _sort);
                  if (mounted) {
                    // [patch] 顺便用返回的 folder_list 刷新文件夹表
                    if (response.folderList.isNotEmpty) {
                      favData = response.folderList;
                      setState(_rebuildFolderMap);
                    }
                  }
                  return InnerComicPage(
                      total: response.total, list: response.list);
                } catch (e) {
                  debugPrient(e);
                  throw StateError("收藏夹加载失败: $e, 请点击重试");
                }
              },
            ),
    );
  }
}
