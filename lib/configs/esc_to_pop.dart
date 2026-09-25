import 'dart:io';

import 'package:flutter/material.dart';

import '../basic/methods.dart';

const _propertyName = "escToPop";
bool _escToPop = false;

Future<void> initEscToPop() async {
  _escToPop = (await methods.loadProperty(_propertyName)) == "true";
}

bool currentEscToPop() {
  return _escToPop;
}

Widget escToPopSetting() {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    return Container();
  }
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return SwitchListTile(
        value: _escToPop,
        onChanged: (value) async {
          await methods.saveProperty(_propertyName, "$value");
          _escToPop = value;
          setState(() {});
        },
        title: const Text("ESC键返回上一页"),
      );
    },
  );
}
