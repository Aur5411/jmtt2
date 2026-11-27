class SortBy {
  final String _value;
  final String _name;

  const SortBy._(this._value, this._name);

  get value => _value;

  @override
  String toString() {
    return _name;
  }
}

const sortByDefault = SortBy._("", "默认");
const sortByNew = SortBy._("mr", "最新");
const sortByLike = SortBy._("tf", "心");
const sortByView = SortBy._("mv", "查看");
const sortByViewDay = SortBy._("mv_t", "日榜");
const sortByViewWeek = SortBy._("mv_w", "周榜");
const sortByViewMonth = SortBy._("mv_m", "月榜");

const sorts = [
  sortByDefault,
  sortByNew,
  sortByLike,
  sortByView,
  sortByViewDay,
  sortByViewWeek,
  sortByViewMonth,
];

int? _parseIntTimestamp(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  return int.tryParse("$value");
}

// [patch] 反序列化容错工具: 服务端偶发少字段/类型漂移(如 FID 传成字符串)时
// 不再整页抛 TypeError, 而是退化成安全默认值, 让列表继续显示
int _asInt(dynamic value, [int fallback = 0]) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value == null) {
    return fallback;
  }
  return int.tryParse("$value") ?? fallback;
}

int? _asIntOrNull(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse("$value");
}

String _asString(dynamic value, [String fallback = ""]) {
  if (value == null) {
    return fallback;
  }
  return value is String ? value : "$value";
}

// [patch] 数值型字段(如 expPercent)容错: 服务端给字符串或不给时退化为 0
double _asDouble(dynamic value, [double fallback = 0]) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value == null) {
    return fallback;
  }
  return double.tryParse("$value") ?? fallback;
}

List<dynamic> _asList(dynamic value) {
  if (value is List) {
    return value;
  }
  return const [];
}

/// [patch] 字符串列表容错: 元素强转失败时按字符串归一, 不整条抛
List<String> _asStringList(dynamic value) {
  final result = <String>[];
  for (final item in _asList(value)) {
    if (item == null) {
      continue;
    }
    result.add(item is String ? item : "$item");
  }
  return result;
}

bool _asBool(dynamic value, [bool fallback = false]) {
  if (value is bool) {
    return value;
  }
  if (value == null) {
    return fallback;
  }
  final s = "$value".toLowerCase();
  if (s == "true" || s == "1") {
    return true;
  }
  if (s == "false" || s == "0") {
    return false;
  }
  return fallback;
}

/// 列表项解析保护: 单条脏数据只跳过这一条, 不会让整个列表加载失败
List<T> _mapList<T>(dynamic value, T Function(Map<String, dynamic>) build) {
  final result = <T>[];
  for (final item in _asList(value)) {
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

class Page<T> {
  late final List<T> list;
  late final int total;
}

class CountPage<T> {
  late final List<T> list;
  late final int total;
  late final int count;

  CountPage.fromJson(Map<String, dynamic> json) {
    // [patch] 缺字段/类型漂移时退化为 0, 不再抛 TypeError 导致整页加载失败
    total = _asInt(json["total"]);
    count = _asInt(json["count"]);
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json["total"] = total;
    json["count"] = count;
    return json;
  }

  CountPage() {
    total = 0;
    count = 0;
  }
}

class SearchPage {
  SearchPage({
    required this.searchQuery,
    required this.total,
  });

  late final String searchQuery;
  late final int total;
  late final int? redirectAid;

  SearchPage.fromJson(Map<String, dynamic> json) {
    // [patch] 容错: search_query/total 缺失或类型不符不再抛
    searchQuery = _asString(json['search_query']);
    total = _asInt(json['total']);
    redirectAid = _asIntOrNull(json['redirect_aid']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['search_query'] = searchQuery;
    _data['total'] = total;
    _data['redirect_aid'] = redirectAid;
    return _data;
  }
}

class ComicsResponse extends SearchPage {
  late final List<ComicSimple> content;

  ComicsResponse.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    // [patch] content 为 null / 含脏条目时不再整页失败
    content = _mapList(json['content'], (e) => ComicSimple.fromJson(e));
  }

  @override
  Map<String, dynamic> toJson() {
    final _data = super.toJson();
    _data['content'] = content;
    return _data;
  }
}

class ComicSimple extends ComicBasic {
  ComicSimple({
    required int id,
    required String author,
    required String description,
    required String name,
    required String image,
    required ComicSimpleCategory category,
    required ComicSimpleCategory categorySub,
    int? updateAt,
    this.sealed = false,
  }) : super(
            id: id,
            author: author,
            description: description,
            name: name,
            image: image,
            category: category,
            categorySub: categorySub,
            updateAt: updateAt);

  bool sealed = false;

  ComicSimple.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    sealed = json['sealed'] == true;
  }

  @override
  Map<String, dynamic> toJson() {
    final _data = super.toJson();
    _data['sealed'] = sealed;
    return _data;
  }
}

class ComicSimpleCategory {
  ComicSimpleCategory({
    this.id,
    this.title,
  });

  late final String? id;
  late final String? title;

  ComicSimpleCategory.fromJson(Map<String, dynamic> json) {
    id = json['id'] == null ? null : "${json['id']}";
    title = json['title'] == null ? null : "${json['title']}";
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['title'] = title;
    return _data;
  }
}

class CategoriesResponse {
  CategoriesResponse({
    required this.categories,
    required this.blocks,
  });

  late final List<Categories> categories;
  late final List<Block> blocks;

  CategoriesResponse.fromJson(Map<String, dynamic> json) {
    // [patch] 容错: 分类接口缺字段时退化为空列表, 不让首页/搜索入口崩
    categories = _mapList(json['categories'], (e) => Categories.fromJson(e));
    blocks = _mapList(json['blocks'], (e) => Block.fromJson(e));
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['categories'] = categories.map((e) => e.toJson()).toList();
    _data['blocks'] = blocks.map((e) => e.toJson()).toList();
    return _data;
  }
}

class Categories {
  Categories({
    required this.id,
    required this.name,
    required this.slug,
    required this.totalAlbums,
    this.type,
  });

  late final int id;
  late final String name;
  late final String slug;
  late final int totalAlbums;
  late final String? type;

  Categories.fromJson(Map<String, dynamic> json) {
    id = _asInt(json['id']);
    name = _asString(json['name']);
    slug = _asString(json['slug']);
    totalAlbums = _asInt(json['total_albums']);
    type = null;
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['name'] = name;
    _data['slug'] = slug;
    _data['total_albums'] = totalAlbums;
    _data['type'] = type;
    return _data;
  }
}

class Block {
  Block({
    required this.title,
    required this.content,
  });

  late final String title;
  late final List<String> content;

  Block.fromJson(Map<String, dynamic> json) {
    title = _asString(json['title']);
    content = _asStringList(json['content']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['title'] = title;
    _data['content'] = content;
    return _data;
  }
}

class AlbumResponse {
  AlbumResponse({
    required this.id,
    required this.name,
    required this.author,
    required this.images,
    required this.description,
    required this.totalViews,
    required this.likes,
    required this.series,
    required this.seriesId,
    required this.commentTotal,
    required this.tags,
    required this.works,
    required this.relatedList,
    required this.liked,
    required this.isFavorite,
    this.addtime,
  });

  late final int id;
  late final String name;
  late final List<String> author;
  late final List<String> images;
  late final String description;
  late final int totalViews;
  late final int likes;
  late final List<Series> series;
  late final int seriesId;
  late final int commentTotal;
  late final List<String> tags;
  late final List<String> works;
  late final List<ComicBasic> relatedList;
  late final bool liked;
  late bool isFavorite;
  late final int? addtime;

  AlbumResponse.fromJson(Map<String, dynamic> json) {
    // [patch] 详情页整条容错: 任一字段缺失/类型漂移不再让详情页白屏,
    // 这直接决定「收藏按钮所在页面能不能打开」
    id = _asInt(json['id']);
    name = _asString(json['name']);
    author = _asStringList(json['author']);
    images = _asStringList(json['images']);
    description = _asString(json['description']);
    totalViews = _asInt(json['total_views']);
    likes = _asInt(json['likes']);
    series = _mapList(json['series'], (e) => Series.fromJson(e));
    seriesId = _asInt(json['series_id']);
    commentTotal = _asInt(json['comment_total']);
    tags = _asStringList(json['tags']);
    works = _asStringList(json['works']);
    relatedList = _mapList(json['related_list'], (e) => ComicBasic.fromJson(e));
    liked = _asBool(json['liked']);
    isFavorite = _asBool(json['is_favorite']);
    addtime = _parseIntTimestamp(json['addtime']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['name'] = name;
    _data['author'] = author;
    _data['images'] = images;
    _data['description'] = description;
    _data['total_views'] = totalViews;
    _data['likes'] = likes;
    _data['series'] = series.map((e) => e.toJson()).toList();
    _data['series_id'] = seriesId;
    _data['comment_total'] = commentTotal;
    _data['tags'] = tags;
    _data['works'] = works;
    _data['related_list'] = relatedList.map((e) => e.toJson()).toList();
    _data['liked'] = liked;
    _data['is_favorite'] = isFavorite;
    _data['addtime'] = addtime;
    return _data;
  }
}

class Series {
  Series({
    required this.id,
    required this.name,
    required this.sort,
  });

  late final int id;
  late final String name;
  late final String sort;

  Series.fromJson(Map<String, dynamic> json) {
    // [patch] 容错: 章节/系列元数据缺字段不再中断详情页解析
    id = _asInt(json['id']);
    name = _asString(json['name']);
    sort = _asString(json['sort']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['name'] = name;
    _data['sort'] = sort;
    return _data;
  }
}

class ComicBasic {
  ComicBasic({
    required this.id,
    required this.author,
    required this.description,
    required this.name,
    required this.image,
    this.updateAt,
    this.addtime,
    this.category,
    this.categorySub,
  });

  late final int id;
  late final String author;
  late final String description;
  late final String name;
  late final String image;
  late final int? updateAt;
  late final int? addtime;
  late final ComicSimpleCategory? category;
  late final ComicSimpleCategory? categorySub;

  ComicBasic.fromJson(Map<String, dynamic> json) {
    // [patch] id 类型漂移(字符串 id)时也能正常解析
    id = _asInt(json['id']);
    author = _asString(json['author']);
    description = _asString(json['description']);
    name = _asString(json['name']);
    image = _asString(json['image']);
    updateAt = _asIntOrNull(json['update_at']);
    addtime = _parseIntTimestamp(json['addtime']);
    category = json['category'] is Map<String, dynamic>
        ? ComicSimpleCategory.fromJson(json['category'])
        : null;
    categorySub = json['category_sub'] is Map<String, dynamic>
        ? ComicSimpleCategory.fromJson(json['category_sub'])
        : null;
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['author'] = author;
    _data['description'] = description;
    _data['name'] = name;
    _data['image'] = image;
    _data['update_at'] = updateAt;
    _data['addtime'] = addtime;
    _data['category'] = category?.toJson();
    _data['category_sub'] = categorySub?.toJson();
    return _data;
  }
}

class ChapterResponse {
  ChapterResponse({
    required this.id,
    required this.series,
    required this.tags,
    required this.name,
    required this.images,
    required this.seriesId,
    required this.isFavorite,
    required this.liked,
  });

  late final int id;
  late final List<Series> series;
  late final String tags;
  late final String name;
  late final List<String> images;
  late final int seriesId;
  late final bool isFavorite;
  late final bool liked;

  ChapterResponse.fromJson(Map<String, dynamic> json) {
    // [patch] 阅读页同款容错, 字段漂移时不再整页白屏
    id = _asInt(json['id']);
    series = _mapList(json['series'], (e) => Series.fromJson(e));
    tags = _asString(json['tags']);
    name = _asString(json['name']);
    images = _asStringList(json['images']);
    seriesId = _asInt(json['series_id']);
    isFavorite = _asBool(json['is_favorite']);
    liked = _asBool(json['liked']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['series'] = series.map((e) => e.toJson()).toList();
    _data['tags'] = tags;
    _data['name'] = name;
    _data['images'] = images;
    _data['series_id'] = seriesId;
    _data['is_favorite'] = isFavorite;
    _data['liked'] = liked;
    return _data;
  }
}

class ImageSize {
  ImageSize({
    required this.h,
    required this.w,
  });

  late final int h;
  late final int w;

  ImageSize.fromJson(Map<String, dynamic> json) {
    h = _asInt(json['h']);
    w = _asInt(json['w']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['h'] = h;
    _data['w'] = w;
    return _data;
  }
}

class Comment {
  Comment({
    required this.AID,
    required this.CID,
    required this.UID,
    required this.username,
    required this.nickname,
    required this.likes,
    required this.gender,
    required this.updateAt,
    required this.addtime,
    required this.parentCID,
    required this.expinfo,
    required this.name,
    required this.content,
    required this.photo,
    required this.spoiler,
    required this.replys,
  });

  late final int? AID;
  late final int CID;
  late final int UID;
  late final String username;
  late final String nickname;
  late final int likes;
  late final String gender;
  late final String updateAt;
  late final String addtime;
  late final int parentCID;
  late final Expinfo expinfo;
  late final String name;
  late final String content;
  late final String photo;
  late final int spoiler;
  late final List<Comment> replys;

  Comment.fromJson(Map<String, dynamic> json) {
    // [patch] 容错: 评论字段缺失/类型漂移不再让整个评论区崩
    AID = _asIntOrNull(json['AID']);
    CID = _asInt(json['CID']);
    UID = _asInt(json['UID']);
    username = _asString(json['username']);
    nickname = _asString(json['nickname']);
    likes = _asInt(json['likes']);
    gender = _asString(json['gender']);
    updateAt = _asString(json['update_at']);
    addtime = _asString(json['addtime']);
    parentCID = _asInt(json['parent_CID']);
    final exp = json['expinfo'];
    expinfo = exp is Map<String, dynamic>
        ? Expinfo.fromJson(exp)
        : Expinfo.fromJson(const {});
    name = _asString(json['name']);
    content = _asString(json['content']);
    photo = _asString(json['photo']);
    spoiler = _asInt(json['spoiler']);
    replys = _mapList(json['replys'], (e) => Comment.fromJson(e));
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['AID'] = AID;
    _data['CID'] = CID;
    _data['UID'] = UID;
    _data['username'] = username;
    _data['nickname'] = nickname;
    _data['likes'] = likes;
    _data['gender'] = gender;
    _data['update_at'] = updateAt;
    _data['addtime'] = addtime;
    _data['parent_CID'] = parentCID;
    _data['expinfo'] = expinfo.toJson();
    _data['name'] = name;
    _data['content'] = content;
    _data['photo'] = photo;
    _data['spoiler'] = spoiler;
    _data['replys'] = replys.map((e) => e.toJson()).toList();
    return _data;
  }
}

class Expinfo {
  Expinfo({
    required this.levelName,
    required this.level,
    required this.nextLevelExp,
    required this.exp,
    required this.expPercent,
    required this.uid,
    required this.badges,
  });

  late final String levelName;
  late final int level;
  late final int nextLevelExp;
  late final String exp;
  late final double expPercent;
  late final int uid;
  late final List<Badge> badges;

  Expinfo.fromJson(Map<String, dynamic> json) {
    // [patch] 容错: 等级信息缺失不再让评论区整页失败
    levelName = _asString(json['level_name']);
    level = _asInt(json['level']);
    nextLevelExp = _asInt(json['nextLevelExp']);
    exp = _asString(json['exp']);
    expPercent = _asDouble(json['expPercent']);
    uid = _asInt(json['uid']);
    badges = _mapList(json['badges'], (e) => Badge.fromJson(e));
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['level_name'] = levelName;
    _data['level'] = level;
    _data['nextLevelExp'] = nextLevelExp;
    _data['exp'] = exp;
    _data['expPercent'] = expPercent;
    _data['uid'] = uid;
    _data['badges'] = badges.map((e) => e.toJson()).toList();
    return _data;
  }
}

class Badge {
  Badge({
    required this.content,
    required this.name,
    required this.id,
  });

  late final String content;
  late final String name;
  late final String id;

  Badge.fromJson(Map<String, dynamic> json) {
    content = _asString(json['content']);
    name = _asString(json['name']);
    id = _asString(json['id']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['content'] = content;
    _data['name'] = name;
    _data['id'] = id;
    return _data;
  }
}

class CommentPage extends Page<Comment> {
  CommentPage.fromJson(Map<String, dynamic> json) {
    list = _mapList(json['list'], (e) => Comment.fromJson(e));
    total = _asInt(json['total']);
  }
}

class PreLoginResponse {
  PreLoginResponse({
    required this.preSet,
    required this.preLogin,
    required this.selfInfo,
    required this.message,
  });

  late final bool preSet;
  late final bool preLogin;
  late final SelfInfo? selfInfo;
  late final String? message;

  PreLoginResponse.fromJson(Map<String, dynamic> json) {
    // [patch] 容错: 登录状态探测缺字段时按未登录处理, 不再让启动流程直接崩
    preSet = _asBool(json['pre_set']);
    preLogin = _asBool(json['pre_login']);
    final raw = json['self_info'];
    if (raw is Map<String, dynamic>) {
      try {
        selfInfo = SelfInfo.fromJson(raw);
      } catch (_) {
        selfInfo = null;
      }
    } else {
      selfInfo = null;
    }
    message = json['message'] == null ? null : _asString(json['message']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['pre_set'] = preSet;
    _data['pre_login'] = preLogin;
    _data['self_info'] = selfInfo?.toJson();
    _data['message'] = message;
    return _data;
  }
}

class SelfInfo {
  SelfInfo({
    required this.uid,
    required this.username,
    required this.email,
    required this.emailverified,
    required this.photo,
    required this.fname,
    required this.gender,
    required this.message,
    required this.coin,
    required this.albumFavorites,
    required this.s,
    required this.levelName,
    required this.level,
    required this.nextLevelExp,
    required this.exp,
    required this.expPercent,
    required this.badges,
    required this.albumFavoritesMax,
  });

  late final int uid;
  late final String username;
  late final String email;
  late final String emailverified;
  late final String photo;
  late final String fname;
  late final String gender;
  late final String message;
  late final int coin;
  late final int albumFavorites;
  late final String s;
  late final String levelName;
  late final int level;
  late final int nextLevelExp;
  late final String exp;
  late final double expPercent;
  late final List<dynamic> badges;
  late final int albumFavoritesMax;

  SelfInfo.fromJson(Map<String, dynamic> json) {
    // [patch] 容错: 账号信息字段漂移(如 badges 缺失)时不再整条抛,
    // 否则「已登录」状态会被误判成掉登录
    uid = _asInt(json['uid']);
    username = _asString(json['username']);
    email = _asString(json['email']);
    emailverified = _asString(json['emailverified']);
    photo = _asString(json['photo']);
    fname = _asString(json['fname']);
    gender = _asString(json['gender']);
    message = _asString(json['message']);
    coin = _asInt(json['coin']);
    albumFavorites = _asInt(json['album_favorites']);
    s = _asString(json['s']);
    levelName = _asString(json['level_name']);
    level = _asInt(json['level']);
    nextLevelExp = _asInt(json['nextLevelExp']);
    exp = _asString(json['exp']);
    expPercent = _asDouble(json['expPercent']);
    badges = _asList(json['badges']);
    albumFavoritesMax = _asInt(json['album_favorites_max']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['uid'] = uid;
    _data['username'] = username;
    _data['email'] = email;
    _data['emailverified'] = emailverified;
    _data['photo'] = photo;
    _data['fname'] = fname;
    _data['gender'] = gender;
    _data['message'] = message;
    _data['coin'] = coin;
    _data['album_favorites'] = albumFavorites;
    _data['s'] = s;
    _data['level_name'] = levelName;
    _data['level'] = level;
    _data['nextLevelExp'] = nextLevelExp;
    _data['exp'] = exp;
    _data['expPercent'] = expPercent;
    _data['badges'] = badges;
    _data['album_favorites_max'] = albumFavoritesMax;
    return _data;
  }
}

class FavoriteFolder {
  FavoriteFolder({
    required this.fid,
    required this.uid,
    required this.name,
  });

  late final String fid;
  late final String uid;
  late final String name;

  FavoriteFolder.fromJson(Map<String, dynamic> json) {
    // [patch] 容错解析
    fid = _asString(json['FID']);
    uid = _asString(json['UID']);
    name = _asString(json['name']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['FID'] = fid;
    _data['UID'] = uid;
    _data['name'] = name;
    return _data;
  }
}

class Favorite extends CountPage<ComicSimple> {
  late final List<FavoriteFolderItem> folderList;
  Favorite.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    // [patch] list / folder_list 任一缺失都不再整页失败: 缺一个就退化成空列表
    list = _mapList(json['list'], (e) => ComicSimple.fromJson(e));
    folderList =
        _mapList(json['folder_list'], (e) => FavoriteFolderItem.fromJson(e));
  }

  @override
  Map<String, dynamic> toJson() {
    final _data = super.toJson();
    _data['list'] = list;
    _data['folder_list'] = folderList;
    return _data;
  }

  Favorite(): super() {
    list = [];
    folderList = [];
  }
}

class FavoriteFolderItem {
  FavoriteFolderItem({
    required this.fid,
    required this.uid,
    required this.name,
  });

  late final int fid;
  late final int uid;
  late final String name;

  FavoriteFolderItem.fromJson(Map<String, dynamic> json) {
    // [patch] 接口时序不一致: /favorite 返回 FID 为字符串, /favorites 里为数字,
    // 原实现按 int 硬赋值, 拿到字符串就整页崩 -> 这里统一按数字解析
    fid = _asInt(json['FID']);
    uid = _asInt(json['UID']);
    name = _asString(json['name']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['FID'] = fid;
    _data['UID'] = uid;
    _data['name'] = name;
    return _data;
  }
}

class FavoritesResponse extends CountPage<ComicSimple> {
  FavoritesResponse.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    // [patch] 容错解析
    list = _mapList(json['list'], (e) => ComicSimple.fromJson(e));
  }

  @override
  Map<String, dynamic> toJson() {
    final _data = super.toJson();
    _data['list'] = list;
    return _data;
  }
}

class WeekFilterResponse extends Page<ComicSimple> {
  WeekFilterResponse.fromJson(Map<String, dynamic> json) {
    // [patch] 容错解析
    list = _mapList(json['list'], (e) => ComicSimple.fromJson(e));
    total = _asInt(json['total']);
  }
}

class ActionResponse {
  ActionResponse({
    required this.status,
    required this.msg,
    required this.type,
  });

  late final String status;
  late final String msg;
  late final String type;

  ActionResponse.fromJson(Map<String, dynamic> json) {
    // [patch] 容错: set_favorite 返回缺字段时不再整条抛, 只当作空状态
    status = _asString(json['status']);
    msg = _asString(json['msg']);
    type = _asString(json['type']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['status'] = status;
    _data['msg'] = msg;
    _data['type'] = type;
    return _data;
  }
}

class InnerComicPage {
  final int total;
  final List<ComicSimple> list;
  final int? redirectAid;

  InnerComicPage({
    required this.total,
    required this.list,
    this.redirectAid,
  });
}

class CommentResponse {
  CommentResponse({
    required this.msg,
    required this.status,
    required this.aid,
    required this.cid,
    required this.spoiler,
  });

  late final String msg;
  late final String status;
  late final int aid;
  late final int cid;
  late final String spoiler;

  CommentResponse.fromJson(Map<String, dynamic> json) {
    // [patch] 容错: 发表评论返回缺字段时不再抛, 只退化成本地状态
    msg = _asString(json['msg']);
    status = _asString(json['status']);
    aid = _asInt(json['aid']);
    cid = _asInt(json['cid']);
    spoiler = _asString(json['spoiler']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['msg'] = msg;
    _data['status'] = status;
    _data['aid'] = aid;
    _data['cid'] = cid;
    _data['spoiler'] = spoiler;
    return _data;
  }
}

class ViewLog {
  ViewLog({
    required this.id,
    required this.author,
    required this.description,
    required this.name,
    required this.lastViewTime,
    required this.lastViewChapterId,
    required this.lastViewPage,
  });

  late final int id;
  late final String author;
  late final String description;
  late final String name;
  late final int lastViewTime;
  late final int lastViewChapterId;
  late final int lastViewPage;

  ViewLog.fromJson(Map<String, dynamic> json) {
    id = _asInt(json['id']);
    author = _asString(json['author']);
    description = _asString(json['description']);
    name = _asString(json['name']);
    lastViewTime = _asInt(json['last_view_time']);
    lastViewChapterId = _asInt(json['last_view_chapter_id']);
    lastViewPage = _asInt(json['last_view_page']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['author'] = author;
    _data['description'] = description;
    _data['name'] = name;
    _data['last_view_time'] = lastViewTime;
    _data['last_view_chapter_id'] = lastViewChapterId;
    _data['last_view_page'] = lastViewPage;
    return _data;
  }
}

class GamePage {
  GamePage({
    required this.games,
    required this.gamesTotal,
    required this.categories,
    required this.hotGames,
  });

  late final List<Game> games;
  late final String gamesTotal;
  late final List<GameCategory> categories;
  late final List<Game> hotGames;

  GamePage.fromJson(Map<String, dynamic> json) {
    // [patch] 容错: 游戏页字段缺失不再整页失败
    games = _mapList(json['games'], (e) => Game.fromJson(e));
    gamesTotal = _asString(json['games_total']);
    categories = _mapList(json['categories'], (e) => GameCategory.fromJson(e));
    hotGames = _mapList(json['hot_games'], (e) => Game.fromJson(e));
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['games'] = games.map((e) => e.toJson()).toList();
    _data['games_total'] = gamesTotal;
    _data['categories'] = categories.map((e) => e.toJson()).toList();
    _data['hot_games'] = hotGames.map((e) => e.toJson()).toList();
    return _data;
  }
}

class Game {
  Game({
    required this.gid,
    required this.title,
    required this.description,
    required this.tags,
    required this.link,
    required this.linkTitle,
    required this.photo,
    required this.type,
    required this.categories,
    required this.updateAt,
    required this.totalClicks,
    required this.orderRank,
    required this.status,
    required this.showLang,
  });

  late final int gid;
  late final String title;
  late final String description;
  late final String tags;
  late final String link;
  late final String linkTitle;
  late final String photo;
  late final List<String> type;
  late final GameCategory categories;
  late final int updateAt;
  late final int totalClicks;
  late final int orderRank;
  late final int status;
  late final List<String> showLang;

  Game.fromJson(Map<String, dynamic> json) {
    gid = _asInt(json['gid']);
    title = _asString(json['title']);
    description = _asString(json['description']);
    tags = _asString(json['tags']);
    link = _asString(json['link']);
    linkTitle = _asString(json['link_title']);
    photo = _asString(json['photo']);
    type = _asStringList(json['type']);
    final category = json['categories'];
    categories = category is Map<String, dynamic>
        ? GameCategory.fromJson(category)
        : GameCategory.fromJson(const {});
    updateAt = _asInt(json['update_at']);
    totalClicks = _asInt(json['total_clicks']);
    orderRank = _asInt(json['order_rank']);
    status = _asInt(json['status']);
    showLang = _asStringList(json['show_lang']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['gid'] = gid;
    _data['title'] = title;
    _data['description'] = description;
    _data['tags'] = tags;
    _data['link'] = link;
    _data['link_title'] = linkTitle;
    _data['photo'] = photo;
    _data['type'] = type;
    _data['categories'] = categories.toJson();
    _data['update_at'] = updateAt;
    _data['total_clicks'] = totalClicks;
    _data['order_rank'] = orderRank;
    _data['status'] = status;
    _data['show_lang'] = showLang;
    return _data;
  }
}

class GameCategory {
  GameCategory({
    this.name,
    this.slug,
  });

  late final String? name;
  late final String? slug;

  GameCategory.fromJson(Map<String, dynamic> json) {
    name = null;
    slug = null;
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['name'] = name;
    _data['slug'] = slug;
    return _data;
  }
}

class SearchHistory {
  SearchHistory({
    required this.searchQuery,
    required this.lastSearchTime,
  });

  late final String searchQuery;
  late final int lastSearchTime;

  SearchHistory.fromJson(Map<String, dynamic> json) {
    // [patch] 容错: 历史记录缺字段时退化为空关键词, 不再让搜索面板崩
    searchQuery = _asString(json['search_query']);
    lastSearchTime = _asInt(json['last_search_time']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['search_query'] = searchQuery;
    _data['last_search_time'] = lastSearchTime;
    return _data;
  }
}

class DownloadCreate {
  DownloadCreate({
    required this.album,
    required this.chapters,
  });

  late final DownloadCreateAlbum album;
  late final List<DownloadCreateChapter> chapters;

  DownloadCreate.fromJson(Map<String, dynamic> json) {
    final rawAlbum = json['album'];
    album = rawAlbum is Map<String, dynamic>
        ? DownloadCreateAlbum.fromJson(rawAlbum)
        : DownloadCreateAlbum.fromJson(const {});
    chapters =
        _mapList(json['chapters'], (e) => DownloadCreateChapter.fromJson(e));
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['album'] = album.toJson();
    _data['chapters'] = chapters.map((e) => e.toJson()).toList();
    return _data;
  }
}

class DownloadCreateAlbum {
  DownloadCreateAlbum({
    required this.id,
    required this.name,
    required this.author,
    required this.tags,
    required this.works,
    required this.description,
  });

  late final int id;
  late final String name;
  late final List<String> author;
  late final List<String> tags;
  late final List<String> works;
  late final String description;

  DownloadCreateAlbum.fromJson(Map<String, dynamic> json) {
    id = _asInt(json['id']);
    name = _asString(json['name']);
    author = _asStringList(json['author']);
    tags = _asStringList(json['tags']);
    works = _asStringList(json['works']);
    description = _asString(json['description']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['name'] = name;
    _data['author'] = author;
    _data['tags'] = tags;
    _data['works'] = works;
    _data['description'] = description;
    return _data;
  }
}

class DownloadCreateChapter {
  DownloadCreateChapter({
    required this.id,
    required this.name,
    required this.sort,
  });

  late final int id;
  late final String name;
  late final String sort;

  DownloadCreateChapter.fromJson(Map<String, dynamic> json) {
    id = _asInt(json['id']);
    name = _asString(json['name']);
    sort = _asString(json['sort']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['name'] = name;
    _data['sort'] = sort;
    return _data;
  }
}

class DownloadAlbum {
  DownloadAlbum({
    required this.id,
    required this.name,
    required this.author,
    required this.tags,
    required this.works,
    required this.description,
    required this.dlSquareCoverStatus,
    required this.dl_3x4CoverStatus,
    required this.dlStatus,
    required this.imageCount,
    required this.dledImageCount,
  });

  late final int id;
  late final String name;
  late final String author;
  late final String tags;
  late final String works;
  late final String description;
  late final int dlSquareCoverStatus;
  late final int dl_3x4CoverStatus;
  late final int dlStatus;
  late final int imageCount;
  late final int dledImageCount;

  DownloadAlbum.fromJson(Map<String, dynamic> json) {
    id = _asInt(json['id']);
    name = _asString(json['name']);
    author = _asString(json['author']);
    tags = _asString(json['tags']);
    works = _asString(json['works']);
    description = _asString(json['description']);
    dlSquareCoverStatus = _asInt(json['dl_square_cover_status']);
    dl_3x4CoverStatus = _asInt(json['dl_3x4_cover_status']);
    dlStatus = _asInt(json['dl_status']);
    imageCount = _asInt(json['image_count']);
    dledImageCount = _asInt(json['dled_image_count']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['name'] = name;
    _data['author'] = author;
    _data['tags'] = tags;
    _data['works'] = works;
    _data['description'] = description;
    _data['dl_square_cover_status'] = dlSquareCoverStatus;
    _data['dl_3x4_cover_status'] = dl_3x4CoverStatus;
    _data['dl_status'] = dlStatus;
    _data['image_count'] = imageCount;
    _data['dled_image_count'] = dledImageCount;
    return _data;
  }
}

class DlImage {
  DlImage({
    required this.albumId,
    required this.chapterId,
    required this.imageIndex,
    required this.name,
    required this.key,
    required this.dlStatus,
    required this.width,
    required this.height,
  });

  late final int albumId;
  late final int chapterId;
  late final int imageIndex;
  late final String name;
  late final String key;
  late final int dlStatus;
  late final int width;
  late final int height;

  DlImage.fromJson(Map<String, dynamic> json) {
    albumId = _asInt(json['album_id']);
    chapterId = _asInt(json['chapter_id']);
    imageIndex = _asInt(json['image_index']);
    name = _asString(json['name']);
    key = _asString(json['key']);
    dlStatus = _asInt(json['dl_status']);
    width = _asInt(json['width']);
    height = _asInt(json['height']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['album_id'] = albumId;
    _data['chapter_id'] = chapterId;
    _data['image_index'] = imageIndex;
    _data['name'] = name;
    _data['key'] = key;
    _data['dl_status'] = dlStatus;
    _data['width'] = width;
    _data['height'] = height;
    return _data;
  }
}

ComicBasic albumToSimple(AlbumResponse album, ComicBasic? bk) {
  return ComicBasic(
    id: album.id,
    description: album.description,
    name: album.name,
    author: album.author.join(" / "),
    image: album.images.isEmpty ? '' : album.images[0],
    addtime: album.addtime,
    updateAt: bk?.updateAt
  );
}

class IsPro {
  late bool isPro;
  late int expire;

  IsPro.fromJson(Map<String, dynamic> json) {
    // [patch] 容错: is_pro 缺字段时不要抛, 否则 Pro 判定失败会连带
    // 收藏/搜索被当成非 Pro 限制(页码受限、功能灰)
    isPro = _asBool(json["is_pro"]);
    expire = _asInt(json["expire"]);
  }
}

class ProInfoAll {
  late ProInfoAf proInfoAf;
  late ProInfoPat proInfoPat;

  ProInfoAll.fromJson(Map<String, dynamic> json) {
    proInfoAf = ProInfoAf.fromJson(
        json["pro_info_af"] is Map<String, dynamic> ? json["pro_info_af"] : {});
    proInfoPat = ProInfoPat.fromJson(
        json["pro_info_pat"] is Map<String, dynamic> ? json["pro_info_pat"] : {});
  }
}

class ProInfoAf {
  late bool isPro;
  late int expire;

  ProInfoAf.fromJson(Map<String, dynamic> json) {
    isPro = _asBool(json["is_pro"]);
    expire = _asInt(json["expire"]);
  }
}

class ProInfoPat {
  late bool isPro;
  late String patId;
  late String bindUid;
  late int requestDelete;
  late int reBind;
  late int errorType;
  late String errorMsg;
  late String accessKey;

  ProInfoPat.fromJson(Map<String, dynamic> json) {
    isPro = _asBool(json["is_pro"]);
    patId = _asString(json["pat_id"]);
    bindUid = _asString(json["bind_uid"]);
    requestDelete = _asInt(json["request_delete"]);
    reBind = _asInt(json["re_bind"]);
    errorType = _asInt(json["error_type"]);
    errorMsg = _asString(json["error_msg"]);
    accessKey = _asString(json["access_key"]);
  }
}

class WeekData {
  late List<WeekCategory> categories;
  late List<WeekType> types;

  WeekData.fromJson(Map<String, dynamic> json) {
    // [patch] 容错: 周表接口字段缺失时退化成空列表
    categories = _mapList(json['categories'], (e) => WeekCategory.fromJson(e));
    types = _mapList(json['type'], (e) => WeekType.fromJson(e));
  }
}

class WeekCategory {
  late String id;
  late String time;
  late String title;

  WeekCategory.fromJson(Map<String, dynamic> json) {
    id = _asString(json['id']);
    time = _asString(json['time']);
    title = _asString(json['title']);
  }
}

class WeekType {
  late String id;
  late String title;

  WeekType.fromJson(Map<String, dynamic> json) {
    id = _asString(json['id']);
    title = _asString(json['title']);
  }
}
