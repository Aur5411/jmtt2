import 'package:flutter/material.dart';

// [patch] 推广面板整块停用: 服务端 config_links 下发的所有条目
// (pika客户端 / hanime客户端 / 网络加速 等) 一律不再展示。
// 保留这个类是为了不破坏既有 import 路径, 内容恒为空。
class RecommendLinksPanel extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  const RecommendLinksPanel({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
