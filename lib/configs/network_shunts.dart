import 'package:flutter/material.dart';
import 'package:jasmine/basic/commons.dart';
import 'package:jasmine/basic/log.dart';
import 'package:jasmine/basic/methods.dart';

// [patch] 分流设置移植自上游 ComicSparks/jasmine 的 network_shunts.dart
// 上游把「API 分流」和「图片分流」合并成一套实现, 候选域名不再硬编码在 Dart 层,
// 而是由 Rust 侧 (load_*_host_options / update_shunts) 下发并持久化。
// 旧版本把 4 个 API 域名、9 个 CDN 域名焊死在 Dart 里, 官方换域名后
// 这些写死的域名陆续 404 / 502, 表现就是「搜索转圈」「图片刷不出来」。

/// 分流候选列表的版本号: Rust 侧域名列表变化后自增, 触发设置页刷新
final ValueNotifier<int> shuntListsRevision = ValueNotifier(0);

String _apiHost = "";

String _cdnHost = "";

String get currentApiHostName => _apiHost;

String get currentCdnHostName => _cdnHost;

/// [patch] 兜底候选: 仅在 Rust 侧 load_*_host_options 不可用(旧版后端)时使用,
/// 内容与上游 librust.so 内置的官方域名保持一致
const List<String> _fallbackApiHosts = [
  "www.cdnutc.cc",
  "www.cdngwc.net",
  "www.cdngwc.club",
  "www.cdnbtd.cc",
];

/// [patch] 已知「能连通但章节图片列表为空」的 API 域名, 自动选源和阅读页换源都会跳过它。
/// 实测 (2026-11-27, 同一批章节分别请求 /chapter?id=):
///   www.cdnbtd.cc      → images=[]        (1493280 / 1020687 / 1023582 / 1125424 四次全为 0)
///   www.cdngwc.net     → images=197/344/238/231
///   www.cdngwc.club    → 197
///   www.cdnbea.net     → 197
///   www.cdnhth.net     → 197
///   www.cdnutc.cc      → 197 (偶发超时)
/// 该域名的 album 接口是正常的(章节数 109 都对), 只有 chapter 的 images 被吞成空数组,
/// 所以延迟测速发现不了问题, 只会在点开章节时表现为「本章节没有图片内容」。
const Set<String> _badApiHosts = <String>{
  "www.cdnbtd.cc",
};

const List<String> _fallbackCdnHosts = [
  "cdn-msp.jmdanjonproxy.vip",
  "cdn-msp2.jmdanjonproxy.vip",
  "cdn-msp3.jmdanjonproxy.vip",
  "cdn-msp12.jmdanjonproxy.xyz",
  "cdn-msp.jmapiproxy1.cc",
  "cdn-msp.jmapiproxy3.cc",
  "cdn-msp2.jmapiproxy1.cc",
  "cdn-msp2.jmapiproxy3.cc",
  "cdn-msp3.jmapiproxy3.cc",
];

Future<void> initApiHost() async {
  await reloadApiHosts();
  // [patch] 已保存的 API 域名如果是已知「章节图片为空」的域名 (例如老版本测速
  // 选中了 www.cdnbtd.cc), 启动时直接换掉, 避免用户点开章节才发现没内容
  if (isBadApiHost(_apiHost)) {
    try {
      final candidates = await otherApiHostCandidates();
      if (candidates.isNotEmpty) {
        final target = candidates.first;
        debugPrient("当前 API 域名(${_apiHost})章节图片为空, 启动时自动切换到 $target");
        await methods.saveApiHost(target);
        _apiHost = target;
        shuntListsRevision.value++;
      }
    } catch (e) {
      debugPrient("启动时替换空图片 API 域名失败: $e");
    }
  }
}

Future<void> initCdnHost() async {
  await reloadCdnHosts();
}

Future<void> reloadApiHosts() async {
  try {
    _apiHost = await methods.loadApiHost();
  } catch (e) {
    // [patch] 读取失败保留上一次的值, 不再把空的 host 显示到设置页
    debugPrient("loadApiHost failed: $e");
  }
}

Future<void> reloadCdnHosts() async {
  try {
    _cdnHost = await methods.loadCdnHost();
  } catch (e) {
    debugPrient("loadCdnHost failed: $e");
  }
}

Future<void> refreshShuntLists() async {
  await reloadApiHosts();
  await reloadCdnHosts();
  shuntListsRevision.value++;
}

/// [patch] 给定域名是否是已知「章节图片为空」的 API 域名
bool isBadApiHost(String host) => _badApiHosts.contains(host.trim());

/// [patch] 阅读页遇到空 images 时用来换源: 返回除当前域名外的其它候选 API 域名,
/// 优先剔除已知空图片域名
Future<List<String>> otherApiHostCandidates() async {
  List<String> candidates;
  try {
    candidates = (await methods.loadApiHostOptions()).visible;
  } catch (e) {
    debugPrient("load host options failed: $e");
    candidates = <String>[];
  }
  if (candidates.isEmpty) {
    candidates = _fallbackApiHosts;
  }
  final current = _apiHost;
  final list = candidates
      .where((e) => e.isNotEmpty && e != current && !isBadApiHost(e))
      .toList();
  if (list.isNotEmpty) {
    return list;
  }
  // 全部候选都不理想, 至少换掉当前这个
  return candidates.where((e) => e.isNotEmpty && e != current).toList();
}

/// [patch] 启动时并发测速, 自动切到延迟最低的 API / 图片源。
/// 候选来自 Rust 侧下发列表, 取不到时退回内置兜底列表。
Future<void> autoSelectBestHosts() async {
  await Future.wait([
    _autoSelectBest(
      load: methods.loadApiHostOptions,
      ping: methods.ping,
      save: methods.saveApiHost,
      fallback: _fallbackApiHosts,
      current: () => _apiHost,
      assign: (v) => _apiHost = v,
      // [patch] 延迟最低不代表有内容, 已知空图片域名一律不自动选
      exclude: _badApiHosts,
    ),
    _autoSelectBest(
      load: methods.loadCdnHostOptions,
      ping: methods.pingCdn,
      save: methods.saveCdnHost,
      fallback: _fallbackCdnHosts,
      current: () => _cdnHost,
      assign: (v) => _cdnHost = v,
    ),
  ]);
  shuntListsRevision.value++;
}

Future<void> _autoSelectBest({
  required Future<HostOptions> Function() load,
  required Future<int> Function(String host) ping,
  required Future Function(String host) save,
  required List<String> fallback,
  required String Function() current,
  required void Function(String) assign,
  Set<String> exclude = const <String>{},
}) async {
  try {
    List<String> candidates;
    try {
      candidates = (await load()).visible;
    } catch (e) {
      debugPrient("load host options failed: $e");
      candidates = <String>[];
    }
    if (candidates.isEmpty) {
      candidates = fallback;
    }
    // [patch] 剔除已知不可用的域名 (例如章节图片恒为空的 www.cdnbtd.cc)
    if (exclude.isNotEmpty) {
      final filtered =
          candidates.where((e) => !exclude.contains(e.trim())).toList();
      if (filtered.isNotEmpty) {
        candidates = filtered;
      }
    }
    final results = <MapEntry<String, int>>[];
    await Future.wait(candidates.map((host) async {
      try {
        final latency = await ping(host).timeout(const Duration(seconds: 8));
        if (latency > 0) {
          results.add(MapEntry(host, latency));
        }
      } catch (_) {}
    }));
    if (results.isEmpty) {
      return;
    }
    results.sort((a, b) => a.value.compareTo(b.value));
    final best = results.first.key;
    if (best.isEmpty || best == current()) {
      return;
    }
    await save(best);
    assign(best);
  } catch (e) {
    debugPrient("auto select best host failed: $e");
  }
}

Future<void> chooseApiHost(BuildContext context) async {
  final choose = await showHostDialog(
    context: context,
    title: "API分流",
    manualTitle: "自定义 API 域名",
    load: methods.loadApiHostOptions,
    ping: methods.ping,
    addCustom: methods.addApiHostCustom,
    removeCustom: methods.removeApiHostCustom,
  );
  if (choose != null && choose.isNotEmpty) {
    await methods.saveApiHost(choose);
    await reloadApiHosts();
  }
}

Future<void> chooseCdnHost(BuildContext context) async {
  final choose = await showHostDialog(
    context: context,
    title: "图片分流",
    manualTitle: "自定义图片域名",
    load: methods.loadCdnHostOptions,
    ping: methods.pingCdn,
    addCustom: methods.addCdnHostCustom,
    removeCustom: methods.removeCdnHostCustom,
  );
  if (choose != null && choose.isNotEmpty) {
    await methods.saveCdnHost(choose);
    await reloadCdnHosts();
  }
}

Widget apiHostSetting() {
  return ValueListenableBuilder<int>(
    valueListenable: shuntListsRevision,
    builder: (context, value, child) {
      return ListTile(
        onTap: () async {
          await chooseApiHost(context);
          shuntListsRevision.value++;
        },
        title: const Text("API分流"),
        subtitle: Text(_apiHost.isEmpty ? "(未设置)" : _apiHost),
      );
    },
  );
}

Widget cdnHostSetting() {
  return ValueListenableBuilder<int>(
    valueListenable: shuntListsRevision,
    builder: (context, value, child) {
      return ListTile(
        onTap: () async {
          await chooseCdnHost(context);
          shuntListsRevision.value++;
        },
        title: const Text("图片分流"),
        subtitle: Text(_cdnHost.isEmpty ? "(未设置)" : _cdnHost),
      );
    },
  );
}

Widget updateShuntsSetting() {
  return const UpdateShuntsTile();
}

class UpdateShuntsTile extends StatefulWidget {
  const UpdateShuntsTile({Key? key}) : super(key: key);

  @override
  State<UpdateShuntsTile> createState() => _UpdateShuntsTileState();
}

class _UpdateShuntsTileState extends State<UpdateShuntsTile> {
  bool _busy = false;

  Future<void> _update() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      final result = await methods.updateShunts();
      await refreshShuntLists();
      if (!mounted) {
        return;
      }
      defaultToast(context, result.message);
    } catch (e) {
      if (!mounted) {
        return;
      }
      defaultToast(context, "$e");
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: _busy ? null : _update,
      title: const Text("更新分流"),
      subtitle: Text(_busy ? "正在更新 API 和图片域名" : "刷新 API 和图片域名"),
      trailing: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync),
    );
  }
}

Future<String?> showHostDialog({
  required BuildContext context,
  required String title,
  required String manualTitle,
  required Future<HostOptions> Function() load,
  required Future<int> Function(String host) ping,
  required Future<String> Function(String host) addCustom,
  required Future<void> Function(String host) removeCustom,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) {
      return _HostDialog(
        title: title,
        manualTitle: manualTitle,
        load: load,
        ping: ping,
        addCustom: addCustom,
        removeCustom: removeCustom,
      );
    },
  );
}

class _HostDialog extends StatefulWidget {
  final String title;
  final String manualTitle;
  final Future<HostOptions> Function() load;
  final Future<int> Function(String host) ping;
  final Future<String> Function(String host) addCustom;
  final Future<void> Function(String host) removeCustom;

  const _HostDialog({
    required this.title,
    required this.manualTitle,
    required this.load,
    required this.ping,
    required this.addCustom,
    required this.removeCustom,
  });

  @override
  State<_HostDialog> createState() => _HostDialogState();
}

class _HostDialogState extends State<_HostDialog> {
  HostOptions? _options;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final options = await widget.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _options = options;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
      });
    }
  }

  Future<void> _add() async {
    final host = await _inputHost(context, widget.manualTitle);
    if (host == null || host.isEmpty || !mounted) {
      return;
    }
    try {
      final saved = await widget.addCustom(host);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) {
        return;
      }
      defaultToast(context, "$error");
    }
  }

  Future<void> _remove(String host) async {
    try {
      await widget.removeCustom(host);
      await refreshShuntLists();
      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      defaultToast(context, "$error");
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.45,
        child: options == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("$_error", textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _reload,
                            child: const Text("重试"),
                          ),
                        ],
                      ),
              )
            : ListView(
                children: [
                  for (final host in options.visible)
                    _HostOptionRow(
                      host: host,
                      custom: options.isCustom(host),
                      ping: widget.ping(host),
                      onTap: () => Navigator.of(context).pop(host),
                      onDelete:
                          options.isCustom(host) ? () => _remove(host) : null,
                    ),
                  if (options.visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text("暂无可用域名, 可手动添加"),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _add,
          child: const Text("自定义域名"),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("取消"),
        ),
      ],
    );
  }
}

Future<String?> _inputHost(BuildContext context, String title) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "www.example.com",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text("确定"),
          ),
        ],
      );
    },
  );
  controller.dispose();
  if (result == null || result.isEmpty) {
    return null;
  }
  return result;
}

class _HostOptionRow extends StatelessWidget {
  final String host;
  final bool custom;
  final Future<int> ping;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _HostOptionRow({
    required this.host,
    required this.custom,
    required this.ping,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(host)),
            FutureBuilder<int>(
              future: ping,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const _PingStatus("测速中", Colors.blue);
                }
                if (snapshot.hasError) {
                  return const _PingStatus("失败", Colors.red);
                }
                final latency = snapshot.data ?? -1;
                if (latency <= 0) {
                  return const _PingStatus("失败", Colors.red);
                }
                if (latency <= 200) {
                  return _PingStatus("${latency}ms", Colors.green);
                }
                if (latency <= 500) {
                  return _PingStatus("${latency}ms", Colors.yellow);
                }
                return _PingStatus("${latency}ms", Colors.orange);
              },
            ),
            if (onDelete != null)
              IconButton(
                tooltip: custom ? "删除自定义域名" : null,
                onPressed: onDelete,
                icon: const Icon(Icons.close, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

class _PingStatus extends StatelessWidget {
  final String title;
  final Color color;

  const _PingStatus(this.title, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('\u2022', style: TextStyle(color: color)),
        Text(" $title"),
      ],
    );
  }
}
