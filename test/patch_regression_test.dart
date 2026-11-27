// [patch] 回归测试: 覆盖「收藏 / 搜索偶发不可用」的四类根因。
//
// 运行: flutter test test/patch_regression_test.dart
//
// 这些用例不依赖网络与 Rust 后端, 只验证反序列化容错与分流转发数据结构的
// 行为, 用来确保服务端字段缺失/类型漂移时列表仍然能显示, 而不是整页抛异常。
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/entities.dart';
import 'package:jasmine/basic/methods.dart';

void main() {
  group('收藏: 反序列化容错', () {
    test('Favorite.fromJson 缺 list / folder_list 时降级为空列表', () {
      final favorite = Favorite.fromJson(<String, dynamic>{});
      expect(favorite.list, isEmpty);
      expect(favorite.folderList, isEmpty);
      expect(favorite.total, 0);
    });

    test('FavoriteFolderItem.fromJson: FID 为字符串也能解析成数字', () {
      // 这是「收藏夹列表偶发空白」的直接根因: /favorite 返回的 FID 有时是字符串
      final item = FavoriteFolderItem.fromJson(
          <String, dynamic>{'FID': '12345', 'UID': '999', 'name': '默认'});
      expect(item.fid, 12345);
      expect(item.uid, 999);
      expect(item.name, '默认');
    });

    test('FavoriteFolderItem.fromJson: 字段缺失不抛, 退化为 0 / 空串', () {
      final item = FavoriteFolderItem.fromJson(<String, dynamic>{});
      expect(item.fid, 0);
      expect(item.uid, 0);
      expect(item.name, '');
    });

    test('CountPage.fromJson 缺 total / count 时为 0', () {
      final page = CountPage.fromJson(<String, dynamic>{});
      expect(page.total, 0);
      expect(page.count, 0);
    });

    test('脏条目只跳过单条, 不影响整页', () {
      final favorite = Favorite.fromJson(<String, dynamic>{
        'total': 3,
        'list': <dynamic>[
          <String, dynamic>{'id': 1, 'name': 'A'},
          'not-a-map', // 脏数据
          <String, dynamic>{'id': 2, 'name': 'B'},
        ],
      });
      expect(favorite.list.length, 2);
      expect(favorite.list.map((e) => e.name).toList(), ['A', 'B']);
    });
  });

  group('搜索: 反序列化容错', () {
    test('SearchPage.fromJson 缺字段时退化为安全默认值', () {
      final page = SearchPage.fromJson(<String, dynamic>{});
      expect(page.searchQuery, '');
      expect(page.total, 0);
      expect(page.redirectAid, isNull);
    });

    test('SearchPage.fromJson 数值字段为字符串也能解析', () {
      final page = SearchPage.fromJson(<String, dynamic>{
        'search_query': 'test',
        'total': '42',
        'redirect_aid': '7',
      });
      expect(page.total, 42);
      expect(page.redirectAid, 7);
    });

    test('ComicsResponse.content 为 null 时为空列表而不是抛异常', () {
      final response = ComicsResponse.fromJson(<String, dynamic>{
        'search_query': 'x',
        'total': 0,
        'content': null,
      });
      expect(response.content, isEmpty);
    });

    test('ComicsResponse 解析时遇到脏条目跳过, 保留合法条目', () {
      final response = ComicsResponse.fromJson(<String, dynamic>{
        'search_query': 'x',
        'total': 2,
        'content': <dynamic>[
          <String, dynamic>{'id': 10, 'name': '合法', 'author': 'a'},
          42,
        ],
      });
      expect(response.content.length, 1);
      expect(response.content.first.id, 10);
    });

    test('ComicSimple.id 为字符串时不影响列表渲染', () {
      final comic = ComicSimple.fromJson(<String, dynamic>{
        'id': '10',
        'name': '标题',
        'author': '作者',
      });
      expect(comic.id, 10);
      expect(comic.name, '标题');
      expect(comic.sealed, isFalse);
    });

    test('ComicSimple.sealed 只在明确 true 时为 true', () {
      expect(ComicSimple.fromJson(<String, dynamic>{'id': 1}).sealed, isFalse);
      expect(ComicSimple.fromJson(<String, dynamic>{'id': 1, 'sealed': true}).sealed,
          isTrue);
      expect(
          ComicSimple.fromJson(<String, dynamic>{'id': 1, 'sealed': 'true'})
              .sealed,
          isFalse); // 严格匹配 == true, 与上游语义一致
    });
  });

  group('分流: HostOptions / UpdateShuntsResult', () {
    test('HostOptions.visible 去重并保持 official 在前', () {
      const options = HostOptions(
        official: ['a.com', 'b.com', 'a.com'],
        custom: ['c.com', 'b.com'],
      );
      expect(options.visible, ['a.com', 'b.com', 'c.com']);
      expect(options.isCustom('c.com'), isTrue);
      expect(options.isCustom('a.com'), isFalse);
    });

    test('HostOptions.fromJson 容忍字段缺失与非列表值', () {
      final options = HostOptions.fromJson(<String, dynamic>{
        'official': 'not-a-list',
        'custom': <dynamic>['  x.com  ', null, ''],
      });
      expect(options.official, isEmpty);
      expect(options.custom, ['x.com']);
    });

    test('UpdateShuntsResult.message 分别报告 API 与图片分流', () {
      final ok = UpdateShuntsResult.fromJson(<String, dynamic>{
        'api_ok': true,
        'cdn_ok': true,
      });
      expect(ok.message, 'API 分流已更新, 图片分流已更新');

      final fail = UpdateShuntsResult.fromJson(<String, dynamic>{
        'api_ok': false,
        'api_error': 'timeout',
        'cdn_ok': true,
      });
      expect(fail.message, 'API 分流更新失败：timeout, 图片分流已更新');
    });
  });
}
