import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:jasmine/basic/comic_seal.dart';
import 'package:jasmine/basic/log.dart';

import 'entities.dart';

export 'entities.dart';

const methods = Methods._();

// [patch] 封面路径缓存: 列表滚动/重复进入时不再重复跨语言查询与磁盘 IO
// (Methods 是 const 单例, 可变缓存只能放文件级)
final Map<String, String> _coverPathCache = {};

// [patch] 分流候选 (对齐上游 ComicSparks/jasmine):
// official 是官方下发的候选域名, custom 是用户手动添加的
class HostOptions {
  final List<String> official;
  final List<String> custom;

  const HostOptions({
    required this.official,
    required this.custom,
  });

  factory HostOptions.fromJson(Map<String, dynamic> json) {
    return HostOptions(
      official: _hostStrings(json["official"]),
      custom: _hostStrings(json["custom"]),
    );
  }

  List<String> get visible {
    final seen = <String>{};
    final hosts = <String>[];
    for (final host in [...official, ...custom]) {
      if (seen.add(host)) {
        hosts.add(host);
      }
    }
    return hosts;
  }

  bool isCustom(String host) => custom.contains(host);
}

List<String> _hostStrings(dynamic value) {
  if (value is! List) {
    return const [];
  }
  final hosts = <String>[];
  for (final item in value) {
    // [patch] 逐项跳过 null/空串: 直接 "$item" 会把 null 变成字符串 "null",
    // 拼出的 https://null 会在测速时白白多一次失败请求
    if (item == null) {
      continue;
    }
    final host = "$item".trim();
    if (host.isNotEmpty) {
      hosts.add(host);
    }
  }
  return hosts;
}

// [patch] 「更新分流」的结果: 分别报告 API 与图片域名是否刷新成功
class UpdateShuntsResult {
  final bool apiOk;
  final bool cdnOk;
  final String apiError;
  final String cdnError;
  final String apiHost;
  final String cdnHost;

  const UpdateShuntsResult({
    required this.apiOk,
    required this.cdnOk,
    required this.apiError,
    required this.cdnError,
    required this.apiHost,
    required this.cdnHost,
  });

  factory UpdateShuntsResult.fromJson(Map<String, dynamic> json) {
    return UpdateShuntsResult(
      apiOk: json["api_ok"] == true,
      cdnOk: json["cdn_ok"] == true,
      apiError: "${json["api_error"] ?? ""}",
      cdnError: "${json["cdn_error"] ?? ""}",
      apiHost: "${json["api_host"] ?? ""}",
      cdnHost: "${json["cdn_host"] ?? ""}",
    );
  }

  String get message {
    final api = apiOk ? "API 分流已更新" : "API 分流更新失败：$apiError";
    final cdn = cdnOk ? "图片分流已更新" : "图片分流更新失败：$cdnError";
    return "$api, $cdn";
  }
}

class Methods {
  const Methods._();

  static const _channel = MethodChannel("methods");
  static HttpClient httpClient = HttpClient();

  /// [patch] 单次通道调用超时: 后端卡住/主线程繁忙时不再无限期挂起
  static const Duration _invokeTimeout = Duration(seconds: 20);

  /// [patch] 只读请求失败自动重试次数(不含首次)
  static const int _invokeRetryTimes = 2;

  /// [patch] 可安全重试的只读方法: 收藏/取消收藏/建删文件夹等写操作不重试,
  /// 避免网络抖动时重复提交产生脏数据
  static const Set<String> _retryableMethods = {
    "init_dart",
    "init_dart2",
    "config_links",
    "app_config",
    "load_property",
    "comics",
    "comic_search",
    "page_view_log",
    "album",
    "chapter",
    "categories",
    "favorites",
    "favorite",
    "forum",
    "games",
    "last_search_histories",
    "all_downloads",
    "pre_login",
    "load_api_host",
    "load_cdn_host",
    // [patch] 分流候选/刷新都是幂等操作, 允许重试
    "load_api_host_options",
    "load_cdn_host_options",
    "update_shunts",
  };

  /// [patch] 这些方法的返回值必须是 JSON 对象/数组; 后端偶发返回空串时
  /// 原来会在调用方 jsonDecode("") 抛裸 FormatException, 界面只显示
  /// 「出错, 点击重试」且不会自动重试 -> 统一在通道层判定为瞬时失败
  static const Set<String> _jsonResponseMethods = {
    "comics",
    "comic_search",
    "page_view_log",
    "album",
    "chapter",
    "categories",
    "favorites",
    "favorite",
    "set_favorite",
    "forum",
    "comment",
    "child_comment",
    "games",
    "last_search_histories",
    "all_downloads",
    "pre_login",
    "login",
    "week",
    "week_filter",
    "config_links",
    "app_config",
    "is_pro",
    "pro_info_all",
    // [patch] 分流接口返回 JSON, 空串/损坏数据按瞬时失败处理
    "load_api_host_options",
    "load_cdn_host_options",
    "update_shunts",
  };

  Future<String> _invoke(String method, dynamic params) async {
    final retryTimes =
        _retryableMethods.contains(method) ? _invokeRetryTimes : 0;
    for (var attempt = 0;; attempt++) {
      try {
        return await _invokeOnce(method, params);
      } on _TransientFailure catch (e) {
        // [patch] 网络抖动/通道未就绪 -> 退避重试, 而不是直接把「功能不可用」抛给用户
        debugPrient("retry $method (${attempt + 1}) : ${e.message}");
        if (attempt >= retryTimes) {
          throw StateError(e.message);
        }
        await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
  }

  Future<String> _invokeOnce(String method, dynamic params) async {
    dynamic raw;
    try {
      raw = await _channel
          .invokeMethod(
              "invoke",
              jsonEncode({
                "method": method,
                "params": params is String ? params : jsonEncode(params),
              }))
          .timeout(_invokeTimeout);
    } on TimeoutException {
      throw _TransientFailure("请求超时($method), 请检查网络后重试");
    } on MissingPluginException {
      throw _TransientFailure("后台服务未就绪($method), 请稍后重试");
    } on PlatformException catch (e) {
      throw _TransientFailure(
          "后台调用失败($method): ${e.message ?? e.code}");
    }
    if (raw == null) {
      throw _TransientFailure("后台返回空响应($method)");
    }
    final resp = raw is String ? raw : "$raw";

    dynamic decoded;
    try {
      decoded = jsonDecode(resp);
    } on FormatException {
      throw _TransientFailure("响应格式异常($method)");
    }
    if (decoded is! Map) {
      throw _TransientFailure("响应结构异常($method)");
    }

    // [patch] 响应解析容错: 后端 error_message/response_data 为 null 时不再炸在赋值处
    var response = _Response.fromJson(decoded);
    if (response.errorMessage.isNotEmpty) {
      throw StateError(response.errorMessage);
    }
    if (_jsonResponseMethods.contains(method)) {
      final data = response.responseData;
      if (data.trim().isEmpty) {
        // [patch] 后端返回「空串当成功」是这里最常见的瞬时故障形态
        throw _TransientFailure("服务端返回空数据($method), 请稍后重试");
      }
      try {
        jsonDecode(data);
      } on FormatException {
        throw _TransientFailure("服务端返回数据损坏($method), 请稍后重试");
      }
    }
    return response.responseData;
  }

  Future init() {
    return _invoke("init_dart", "");
  }

  /// [patch] 统一把后端 JSON 字符串解成 Map: 结构不是对象时抛出可读错误,
  /// 而不是在 fromJson 里抛一条 JSON 类型转换的裸异常
  static Map<String, dynamic> _decodeMap(String rsp, String method) {
    final decoded = jsonDecode(rsp);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    throw StateError("服务端返回结构异常($method)");
  }

  /// [patch] 逐个解析列表项, 单条脏数据只丢这一条
  static List<T> _parseList<T>(
    List<dynamic> raw,
    T Function(Map<String, dynamic>) build,
  ) {
    final result = <T>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      try {
        result.add(build(item.cast<String, dynamic>()));
      } catch (_) {
        continue;
      }
    }
    return result;
  }

  Future init2() {
    return _invoke("init_dart2", "");
  }

  Future<Map<String, String>> configLinks() async {
    final rsp = await _invoke("config_links", "");
    final decoded = jsonDecode(rsp);
    if (decoded is! Map) {
      return {};
    }
    return decoded.map((key, value) => MapEntry("$key", "$value"));
  }

  Future<Map<String, dynamic>> appConfig() async {
    final rsp = await _invoke("app_config", "");
    final decoded = jsonDecode(rsp);
    if (decoded is! Map) {
      return {};
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<String> loadProperty(String propertyKey) {
    return _invoke("load_property", propertyKey);
  }

  Future<String> getStartupImagePath() {
    return _invoke("get_startup_image_path", "");
  }

  Future saveStartupImage(String base64Data) {
    return _invoke("save_startup_image", base64Data);
  }

  Future deleteStartupImage() {
    return _invoke("delete_startup_image", "");
  }

  Future<ComicsResponse> comics(String slug, SortBy sortBy, int page) async {
    final rsp = await _invoke("comics", {
      "categories_slug": slug,
      "sort_by": sortBy.value,
      "page": page,
    });
    final response = ComicsResponse.fromJson(_decodeMap(rsp, "comics"));
    for (final comic in response.content) {
      comic.sealed = matchComicSealedByRules(comic);
    }
    return response;
  }

  Future<ComicsResponse> comicSearch(
    String searchQuery,
    SortBy sortBy,
    int page,
  ) async {
    final rsp = await _invoke("comic_search", {
      "search_query": searchQuery,
      "sort_by": sortBy.value,
      "page": page,
    });
    final response = ComicsResponse.fromJson(_decodeMap(rsp, "comic_search"));
    for (final comic in response.content) {
      comic.sealed = matchComicSealedByRules(comic);
    }
    return response;
  }

  Future<ComicsResponse> pageViewLog(int page) async {
    final rsp = await _invoke("page_view_log", page);
    return ComicsResponse.fromJson(_decodeMap(rsp, "page_view_log"));
  }

  Future<dynamic> deleteViewLogByComicId(int comicId) async {
    final rsp = await _invoke("delete_view_log_by_comic_id", comicId);
    return rsp;
  }

  Future<CategoriesResponse> categories() async {
    return CategoriesResponse.fromJson(
        _decodeMap(await _invoke("categories", ""), "categories"));
  }

  Future saveImageFileToGallery(String path) {
    return _channel.invokeMethod("saveImageFileToGallery", path);
  }

  Future saveProperty(String key, String v) {
    return _invoke("save_property", {"k": key, "v": v});
  }

  Future deleteProperty(String key) {
    return _invoke("delete_property", key);
  }

  Future<AlbumResponse> album(int id, {bool ignoreViewLog = false}) async {
    return AlbumResponse.fromJson(_decodeMap(
        await _invoke("album", {
          "id": id,
          "ignore_view_log": ignoreViewLog,
        }),
        "album"));
  }

  Future<ChapterResponse> chapter(int id) async {
    return ChapterResponse.fromJson(
        _decodeMap(await _invoke("chapter", id), "chapter"));
  }

  Future<CommentPage> forum(String? mode, int? aid, int? uid, int page) async {
    return CommentPage.fromJson(_decodeMap(
        await _invoke("forum", {
          "mode": mode,
          "aid": aid,
          "uid": uid,
          "page": page,
        }),
        "forum"));
  }

  Future<Favorite> favorites(int folderId, int page, String o) async {
    return Favorite.fromJson(
      _decodeMap(
          await _invoke("favorites", {
            "folder_id": folderId,
            "page": page,
            "o": o,
          }),
          "favorites"),
    );
  }

  Future<Favorite> favorite() async {
    return Favorite.fromJson(
      _decodeMap(await _invoke("favorite", ""), "favorite"),
    );
  }

  Future<ActionResponse> setFavorite(int aid) async {
    return ActionResponse.fromJson(
      _decodeMap(await _invoke("set_favorite", aid), "set_favorite"),
    );
  }

  Future createFavoriteFolder(String name) async {
    return _invoke("create_favorite_folder", name);
  }

  Future deleteFavoriteFolder(int folderId) async {
    return _invoke("delete_favorite_folder", folderId);
  }

  Future comicFavoriteFolderMove(int comicId, int folderId) async {
    return _invoke("comic_favorite_folder_move", [comicId, folderId]);
  }

  Future renameFavoriteFolder(int folderId, String name) async {
    return _invoke("rename_favorite_folder", ["$folderId", name]);
  }

  Future<GamePage> games(int page) async {
    return GamePage.fromJson(
      _decodeMap(await _invoke("games", page), "games"),
    );
  }

  Future updateViewLog(int id, int lastViewChapterId, int lastViewPage) {
    return _invoke("update_view_log", {
      "id": id,
      "last_view_chapter_id": lastViewChapterId,
      "last_view_page": lastViewPage,
    });
  }

  Future<ViewLog?> findViewLog(int id) async {
    final decoded = jsonDecode(await _invoke("find_view_log", id));
    if (decoded is! Map) {
      // [patch] 后端返回 null/非对象时视为「没有阅读记录」, 不再崩
      return null;
    }
    return ViewLog.fromJson(decoded.cast<String, dynamic>());
  }

  Future cleanAllCache() async {
    // [patch] 清缓存时同步失效封面路径缓存, 避免指向已删除的文件
    _coverPathCache.clear();
    return _invoke("clean_all_cache", "params");
  }

  Future<String> _cover(String method, int comicId) async {
    final key = "$method:$comicId";
    final cached = _coverPathCache[key];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final path = await _invoke(method, comicId);
    if (path.isNotEmpty) {
      _coverPathCache[key] = path;
    }
    return path;
  }

  Future<String> jm3x4Cover(int comicId) {
    return _cover("jm_3x4_cover", comicId);
  }

  Future<String> jmSquareCover(int comicId) {
    return _cover("jm_square_cover", comicId);
  }

  Future<String> jmPageImage(int id, String imageName) {
    // [patch] 页面图片路径缓存: 翻回上一页 / 重进章节不再重复跨语言查询
    final key = "page:$id:$imageName";
    final cached = _coverPathCache[key];
    if (cached != null && cached.isNotEmpty) {
      return Future.value(cached);
    }
    return _invoke("jm_page_image", {"id": id, "image_name": imageName})
        .then((path) {
      if (path.isNotEmpty) {
        _coverPathCache[key] = path;
      }
      return path;
    });
  }

  /// [patch] 预取页面图片到磁盘缓存, 翻页时直接读本地
  Future<void> preloadPageImage(int id, String imageName) async {
    final key = "page:$id:$imageName";
    if (_coverPathCache.containsKey(key)) {
      return;
    }
    try {
      await jmPageImage(id, imageName);
    } catch (_) {}
  }

  /// [patch] 图片加载失败时失效路径缓存(文件可能已被清理), 下次重新向 Rust 取
  void evictPageImage(int id, String imageName) {
    _coverPathCache.remove("page:$id:$imageName");
  }

  void evictCover(String method, int comicId) {
    _coverPathCache.remove("$method:$comicId");
  }

  Future deleteJmPageImageCache(int id, String imageName) {
    return _invoke(
      "delete_jm_page_image_cache",
      {"id": id, "image_name": imageName},
    );
  }

  Future<String> jmPhotoImage(String imageName) {
    return _invoke("jm_photo_image", imageName);
  }

  Future<ImageSize> imageSize(String path) async {
    return ImageSize.fromJson(
        _decodeMap(await _invoke("image_size", path), "image_size"));
  }

  Future httpGet(String versionUrl) {
    return _invoke("http_get", versionUrl);
  }

  Future<String> loadApiHost() {
    return _invoke("load_api_host", "");
  }

  Future<String> loadCdnHost() {
    return _invoke("load_cdn_host", "");
  }

  Future saveApiHost(String choose) {
    return _invoke("save_api_host", choose);
  }

  Future saveCdnHost(String choose) {
    return _invoke("save_cdn_host", choose);
  }

  // [patch] 分流候选/更新接口 (对齐上游 ComicSparks/jasmine):
  // 旧版把候选域名焊死在 Dart 里, 官方换域名后写死的域名陆续 404/502,
  // 表现为「搜索转圈」「图片刷不出来」。改由 Rust 侧下发并持久化。
  Future<HostOptions> loadApiHostOptions() async {
    return HostOptions.fromJson(
      _decodeMap(
        await _invoke("load_api_host_options", ""),
        "load_api_host_options",
      ),
    );
  }

  Future<HostOptions> loadCdnHostOptions() async {
    return HostOptions.fromJson(
      _decodeMap(
        await _invoke("load_cdn_host_options", ""),
        "load_cdn_host_options",
      ),
    );
  }

  Future<String> addApiHostCustom(String host) {
    return _invoke("add_api_host_custom", host);
  }

  Future removeApiHostCustom(String host) {
    return _invoke("remove_api_host_custom", host);
  }

  Future<String> addCdnHostCustom(String host) {
    return _invoke("add_cdn_host_custom", host);
  }

  Future removeCdnHostCustom(String host) {
    return _invoke("remove_cdn_host_custom", host);
  }

  Future<UpdateShuntsResult> updateShunts() async {
    return UpdateShuntsResult.fromJson(
      _decodeMap(await _invoke("update_shunts", ""), "update_shunts"),
    );
  }

  Future<PreLoginResponse> preLogin() async {
    return PreLoginResponse.fromJson(
      _decodeMap(await _invoke("pre_login", ""), "pre_login"),
    );
  }

  Future<SelfInfo> login(String username, String password) async {
    return SelfInfo.fromJson(
      _decodeMap(
          await _invoke("login", {
            "username": username,
            "password": password,
          }),
          "login"),
    );
  }

  Future logout() async {
    await _invoke("logout", {});
  }

  Future<CommentResponse> commentResponse(int aid, String comment) async {
    return CommentResponse.fromJson(_decodeMap(
        await _invoke("comment", {
          "aid": aid,
          "comment": comment,
        }),
        "comment"));
  }

  Future<CommentResponse> comment(int aid, String comment) async {
    return CommentResponse.fromJson(_decodeMap(
        await _invoke("comment", {
          "aid": aid,
          "comment": comment,
        }),
        "comment"));
  }

  Future<CommentResponse> childComment(
    int aid,
    String comment,
    int? commentId,
  ) async {
    return CommentResponse.fromJson(_decodeMap(
        await _invoke("child_comment", {
          "aid": aid,
          "comment": comment,
          "comment_id": commentId,
        }),
        "child_comment"));
  }

  Future<String> loadUsername() {
    return _invoke("load_username", "");
  }

  Future<String> loadLastLoginUsername() {
    return _invoke("loadLastLoginUsername", "");
  }

  Future<String> loadPassword() {
    return _invoke("load_password", "");
  }

  Future clearViewLog() {
    return _invoke("clear_view_log", "");
  }

  Future<List<SearchHistory>> lastSearchHistories(int count) async {
    // [patch] 接口返回 null/非数组时给空历史, 不再让搜索面板崩掉
    final raw = jsonDecode(await _invoke("last_search_histories", "$count"));
    if (raw is! List) {
      return const [];
    }
    return _parseList(raw, (e) => SearchHistory.fromJson(e));
  }

  /// 下载列表
  Future<List<DownloadAlbum>> allDownloads() async {
    final raw = jsonDecode(await _invoke("all_downloads", ""));
    if (raw is! List) {
      return const [];
    }
    return _parseList(raw, (e) => DownloadAlbum.fromJson(e));
  }

  /// 寻找下载
  Future<DownloadCreate?> downloadById(int id) async {
    var decoded = jsonDecode(await _invoke("download_by_id", "$id"));
    if (decoded is! Map) {
      return null;
    }
    return DownloadCreate.fromJson(decoded.cast<String, dynamic>());
  }

  /// 创建下载
  Future<dynamic> createDownload(DownloadCreate create) async {
    return _invoke("create_download", create);
  }

  /// 下载图片列表
  Future<List<DlImage>> dlImageByChapterId(int id) async {
    final raw = jsonDecode(await _invoke("dl_image_by_chapter_id", "$id"));
    if (raw is! List) {
      return const [];
    }
    return _parseList(raw, (e) => DlImage.fromJson(e));
  }

  Future<dynamic> deleteDownload(int id) async {
    return _invoke("delete_download", id);
  }

  Future<dynamic> renewAllDownloads() async {
    return _invoke("renew_all_downloads", "");
  }

  /// 获取安卓的屏幕刷新率
  Future<List<String>> loadAndroidModes() async {
    return List.of(await _channel.invokeMethod("androidGetModes"))
        .map((e) => "$e")
        .toList();
  }

  /// 设置安卓的屏幕刷新率
  Future setAndroidMode(String androidDisplayMode) {
    return _channel
        .invokeMethod("androidSetMode", {"mode": androidDisplayMode});
  }

  /// 获取安卓的版本
  Future<int> androidGetVersion() async {
    if (Platform.isAndroid) {
      return await _channel.invokeMethod("androidGetVersion", {});
    }
    return 0;
  }

  Future export_jm_jpegs(List<int> idList, String path, bool deleteExported) {
    return _invoke("export_jm_jpegs", {
      "comic_id": idList,
      "dir": path,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_zip(List<int> idList, String path, bool deleteExported) {
    return _invoke("export_jm_zip", {
      "comic_id": idList,
      "dir": path,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_zip_single(
      int id, String folder, String? rename, bool deleteExported) {
    return _invoke("export_jm_zip_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_jpegs_zip_single(
      int id, String folder, String? rename, bool deleteExported) {
    return _invoke("export_jm_jpegs_zip_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_jmi(List<int> idList, String path, bool deleteExported) {
    return _invoke("export_jm_jmi", {
      "comic_id": idList,
      "dir": path,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_jmi_single(
      int id, String folder, String? rename, bool deleteExported) {
    return _invoke("export_jm_jmi_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future export_cbzs_zip_single(
      int id, String folder, String? rename, bool deleteExported) {
    return _invoke("export_cbzs_zip_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_pdf(int id, String folder, bool deleteExported) {
    return _invoke("export_jm_pdf", {
      "comic_id": [id],
      "dir": folder,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_pdf2(int id, String folder, bool deleteExported) {
    return _invoke("export_jm_pdf2", {
      "comic_id": [id],
      "dir": folder,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_epub(List<int> idList, String path, bool deleteExported) {
    return _invoke("export_jm_epub", {
      "comic_id": idList,
      "dir": path,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_epub_single(
      int id, String folder, String? rename, bool deleteExported) {
    return _invoke("export_jm_epub_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future import_jm_zip(String path) {
    debugPrient(path);
    return _invoke("import_jm_zip", path);
  }

  Future import_jm_jmi(String path) {
    debugPrient(path);
    return _invoke("import_jm_jmi", path);
  }

  Future import_jm_dir(String path) {
    debugPrient(path);
    return _invoke("import_jm_dir", path);
  }

  Future<IsPro> isPro() async {
    return IsPro.fromJson(_decodeMap(await _invoke("is_pro", ""), "is_pro"));
  }

  Future<ProInfoAll> proInfoAll() async {
    return ProInfoAll.fromJson(
        _decodeMap(await _invoke("pro_info_all", ""), "pro_info_all"));
  }

  Future reloadPro() {
    return _invoke("reload_pro", "");
  }

  Future inputCdKey(String cdKey) {
    return _invoke("input_cd_key", cdKey);
  }

  Future checkPat(String accessKey) {
    return _invoke("check_pat", accessKey);
  }

  Future bindPatAccount(String accessKey, String username) {
    return _invoke(
        "bind_pat",
        jsonEncode({
          "access_key": accessKey,
          "username": username,
        }));
  }

  Future reloadPatAccount() {
    return _invoke("reload_pat_account", "");
  }

  Future clearPat() {
    return _invoke("clear_pat", "");
  }

  Future<int> load_download_thread() async {
    // [patch] 后端返回空串/非数字时回落默认线程数, 不再 int.parse 崩溃
    return int.tryParse(await _invoke("load_download_thread", "")) ?? 3;
  }

  Future set_download_thread(int count) {
    return _invoke("set_download_thread", "${count}");
  }

  Future clearAllSearchLog() {
    return _invoke("clear_all_search_log", "");
  }

  Future clearASearchLog(String log) {
    return _invoke("clear_a_search_log", log);
  }

  Future setProxy(String url) {
    return _invoke("set_proxy", url);
  }

  Future<String> getProxy() {
    return _invoke("get_proxy", "");
  }

  Future webDavSync(dynamic params) {
    return _invoke("sync_webdav", params);
  }

  Future<String> iosGetDocumentDir() async {
    return await _channel.invokeMethod("iosGetDocumentDir");
  }

  Future<String> androidDefaultExportsDir() async {
    return await _channel.invokeMethod("androidDefaultExportsDir");
  }

  Future<String> getDownloadAndExportTo() async {
    return await _invoke("get_download_and_export_to", "");
  }

  Future<String> getHomeDir() async {
    return await _invoke("getHomeDir", "");
  }

  Future setDownloadAndExportTo(String path) async {
    return await _invoke("set_download_and_export_to", path);
  }

  Future<int> ping(String idx) async {
    debugPrient("PING API $idx");
    // [patch] 探测失败/返回空串时按 -1 处理, 不再让 int.parse 炸掉测速页
    return int.tryParse(await _invoke("ping_server", idx)) ?? -1;
  }

  Future<int> pingCdn(String idx) async {
    debugPrient("PING CDN $idx");
    return int.tryParse(await _invoke("ping_cdn", idx)) ?? -1;
  }

  Future mkdirs(String path) {
    return _invoke("mkdirs", path);
  }

  Future androidMkdirs(String path) async {
    return await _channel.invokeMethod("androidMkdirs", path);
  }

  Future<String> picturesDir() async {
    return await _channel.invokeMethod("picturesDir");
  }

  Future<String> copyPictureToFolder(String folder, String path) async {
    return await _invoke(
      "copyPictureToFolder",
      {
        "folder": folder,
        "path": path,
      },
    );
  }

  Future<bool> verifyAuthentication() async {
    return await _channel.invokeMethod("verifyAuthentication");
  }

  Future<String> daily(int uid) {
    return _invoke("daily", uid);
  }

  Future<WeekData> week(int page) async {
    return WeekData.fromJson(_decodeMap(
        await _invoke("week", {
          "page": page,
        }),
        "week"));
  }

  Future<WeekFilterResponse> weekFilter(
      String categoryId, String typeId, int page) async {
    return WeekFilterResponse.fromJson(_decodeMap(
        await _invoke("week_filter", {
          "category_id": categoryId,
          "type_id": typeId,
          "page": page,
        }),
        "week_filter"));
  }
}

/// [patch] 可重试的瞬时失败(超时/通道未就绪/空响应/脏 JSON), 与业务错误分开
class _TransientFailure implements Exception {
  final String message;

  _TransientFailure(this.message);

  @override
  String toString() => message;
}

class _Response {
  late String errorMessage;
  late String responseData;

  _Response.fromJson(Map json) {
    // [patch] 容错解析: null / 非字符串一律归一成空串, 不再在这里抛类型错误
    final error = json["error_message"];
    final data = json["response_data"];
    errorMessage = error == null ? "" : "$error";
    responseData = data == null ? "" : (data is String ? data : "$data");
  }
}
