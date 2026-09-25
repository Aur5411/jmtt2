import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jasmine/screens/components/mouse_and_touch_scroll_behavior.dart';
import 'package:jasmine/screens/init_screen.dart';
import 'basic/desktop.dart';
import 'basic/navigator.dart';
import 'configs/esc_to_pop.dart';
import 'configs/theme.dart';

void main() async {
  runApp(const Jenny());
}

class Jenny extends StatefulWidget {
  const Jenny({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _JennyState();
}

class _JennyState extends State<Jenny> {

  @override
  void initState() {
    onDesktopStart();
    themeEvent.subscribe(_setState);
    super.initState();
  }

  @override
  void dispose() {
    onDesktopStop();
    themeEvent.unsubscribe(_setState);
    super.dispose();
  }

  _setState(_) {
    setState(() => {});
  }
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      scrollBehavior: mouseAndTouchScrollBehavior,
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      navigatorObservers: [routeObserver],
      builder: (BuildContext context, Widget? child) {
        Widget built = child ?? Container();
        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
          built = Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape &&
                  currentEscToPop()) {
                final navigator = appNavigatorKey.currentState;
                if (navigator != null && navigator.canPop()) {
                  navigator.maybePop();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: built,
          );
        }
        return built;
      },
      home: const InitScreen(),
    );
  }
}
