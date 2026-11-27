// [patch] 分流实现已合并到 network_shunts.dart (对齐上游 ComicSparks/jasmine),
// 这里只做转发, 保持原有 import 路径可用。
export 'network_shunts.dart'
    show
        cdnHostSetting,
        chooseCdnHost,
        currentCdnHostName,
        initCdnHost,
        reloadCdnHosts,
        shuntListsRevision;
