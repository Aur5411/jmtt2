import 'package:event/event.dart';
import '../basic/methods.dart';

var isPro = false;
var isProEx = 0;

ProInfoAf? _proInfoAf;
ProInfoPat? _proInfoPat;

ProInfoAf get proInfoAf => _proInfoAf ?? ProInfoAf.fromJson({"is_pro": false, "expire": 0});
ProInfoPat get proInfoPat => _proInfoPat ?? ProInfoPat.fromJson({"is_pro": false, "pat_id": "", "bind_uid": "", "request_delete": 0, "re_bind": 0, "error_type": 0, "error_msg": "", "access_key": ""});

final proEvent = Event();

Future reloadIsPro() async {
  // [patch] Pro 授权常驻启用: 尝试同步服务端状态, 但无论结果如何一律视为已授权
  try {
    final proInfoAll = await methods.proInfoAll();
    _proInfoAf = proInfoAll.proInfoAf;
    _proInfoPat = proInfoAll.proInfoPat;
  } catch (_) {}

  _proInfoAf = ProInfoAf.fromJson({"is_pro": true, "expire": 253402300799});
  _proInfoPat = ProInfoPat.fromJson({
    "is_pro": true,
    "pat_id": "patched",
    "bind_uid": "",
    "request_delete": 0,
    "re_bind": 0,
    "error_type": 0,
    "error_msg": "",
    "access_key": "",
  });

  isPro = true;
  isProEx = _proInfoAf!.expire;

  proEvent.broadcast();
}
