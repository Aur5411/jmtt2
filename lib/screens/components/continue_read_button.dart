import 'package:flutter/material.dart';
import 'package:jasmine/basic/entities.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/screens/components/my_flat_button.dart';

// [patch] 章节排序容错: sort 为空串/非数字时不再 int.parse 崩溃
int _compareSeriesSort(Series a, Series b) {
  final ai = int.tryParse(a.sort.trim());
  final bi = int.tryParse(b.sort.trim());
  if (ai != null && bi != null) {
    return ai.compareTo(bi);
  }
  if (ai != null) {
    return -1;
  }
  if (bi != null) {
    return 1;
  }
  return a.sort.compareTo(b.sort);
}

// 继续阅读按钮
class ContinueReadButton extends StatefulWidget {
  final Future<ViewLog?> viewFuture;
  final AlbumResponse album;
  final Function(int epOrder, int pictureRank) onChoose;

  const ContinueReadButton({
    Key? key,
    required this.album,
    required this.onChoose,
    required this.viewFuture,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ContinueReadButtonState();
}

class _ContinueReadButtonState extends State<ContinueReadButton> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: widget.viewFuture,
      builder: (BuildContext context, AsyncSnapshot<ViewLog?> snapshot) {
        late void Function() onPressed;
        late String text;
        if (snapshot.connectionState != ConnectionState.done) {
          onPressed = () {};
          text = '加载中';
        } else {
          ViewLog? viewLog = snapshot.data;
          if (viewLog == null || viewLog.lastViewChapterId == 0) {
            if (widget.album.series.isEmpty) {
              return Container();
            }
            onPressed = () {
              if (widget.album.series.isEmpty) {
                widget.onChoose(widget.album.id, 0);
              } else {
                // [patch] 用容错排序, 避免 sort 异常导致按钮点击崩溃
                widget.album.series.sort(_compareSeriesSort);
                widget.onChoose(widget.album.series[0].id, 0);
              }
            };
            text = '从头开始';
          } else {
            onPressed = () {
              widget.onChoose(
                viewLog.lastViewChapterId,
                viewLog.lastViewPage,
              );
            };
            text = '继续阅读'; // todo names and pages
            if (widget.album.series.isNotEmpty) {
              for (var i = 0; i < widget.album.series.length; i++) {
                if (widget.album.series[i].id == viewLog.lastViewChapterId) {
                  text += " (${i + 1}.";
                  if (widget.album.series[i].name.isNotEmpty) {
                    text += widget.album.series[i].name + ".";
                  }
                  text += "P${viewLog.lastViewPage + 1})";
                  break;
                }
              }
            } else {
              text += " (P${viewLog.lastViewPage + 1})";
            }
          }
        }
        return MyFlatButton(title: text, onPressed: onPressed);
      },
    );
  }
}
