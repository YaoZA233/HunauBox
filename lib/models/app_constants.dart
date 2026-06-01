class AppConstants {
  static const String ssoBaseUrl = 'https://sso.hunau.edu.cn';
  static const String ssoLoginUrl = '$ssoBaseUrl/cas/login';
  static const String ssoMainPage = '$ssoBaseUrl/portal/main.html';

  static const String portalBaseUrl = 'https://portal.hunau.edu.cn';
  static const String portalIndexUrl = '$portalBaseUrl/index';
  static const String portalWorkspaceUrl = '$portalBaseUrl/fusion/workspace';
  static String get fusionWorkspaceUrl => portalWorkspaceUrl;

  static const String webvpnBaseUrl = 'https://webvpn.hunau.edu.cn';
  static const String webvpnLoginUrl = '$webvpnBaseUrl/login?cas_login=true';
  static const String webvpnPortalUrl =
    'https://webvpn.hunau.edu.cn/http/77777776706e697374686562657374210d1f5a65ff61eaeb37a91a55f196cb76ec58c7';
  static const String webvpnCookieSyncUrl =
    'https://webvpn.hunau.edu.cn/wengine-vpn/cookie?method=get&host=jwxt.hunau.edu.cn&scheme=http&path=/sso.jsp';

  static String noticeDetailUrl(String id) => '$portalBaseUrl/fusion/notice/detail/$id';

  static const String xgxtBaseUrl = 'https://xgxt.hunau.edu.cn';
  static const String xgxtCasUrl = '$xgxtBaseUrl/cas';
  static const String xgxtWapUrl = '$xgxtBaseUrl/wap/main/welcome';

  static const String jwxtBaseUrl = 'http://jwxt.hunau.edu.cn';
  static const String jwxtSsoUrl =
    'https://webvpn.hunau.edu.cn/http/77777776706e6973746865626573742117075065b065b1ed23b25545bb868160e0/sso.jsp';
  static const String jwxtFrameworkUrl =
    'https://webvpn.hunau.edu.cn/http/77777776706e6973746865626573742117075065b065b1ed23b25545bb868160e0/jsxsd/framework/xsMainV.jsp';
  static const String jwxtCookieSyncUrl = '$jwxtBaseUrl/cookieSync';
  static String jwxtTimetableUrl(String semester) =>
    'https://webvpn.hunau.edu.cn/http/77777776706e6973746865626573742117075065b065b1ed23b25545bb868160e0/jsxsd/xskb/xskb_list.do?xnxq01id=$semester';

  static const String casLoginUrl = 'https://cas.hunau.edu.cn/cas/login';
  static const String casServiceForJwxt = jwxtSsoUrl;

  static const String fusionUserInfoUrl = '$portalBaseUrl/fusion/personal/getUserInfo';
  static String fusionAvatarUrl(String uid) => 'https://photo.chaoxing.com/p/${uid}_480';
  static const String fusionMessageListUrl = '$portalBaseUrl/fusion/message/getMessageListByWfw';
  static const String fusionMessageCookieSyncUrl = '$portalBaseUrl/fusion/page/toMessage';

  static const String chaoxingNoticeBaseUrl = 'https://notice.chaoxing.com';
  static const String chaoxingNoticeListUrl = '$chaoxingNoticeBaseUrl/pc/notice/getNoticeList';
  static String chaoxingNoticeDetailUrl(String uuid) =>
    '$chaoxingNoticeBaseUrl/pc/notice/$uuid/detail?sendTag=0';

  static const String teachingEvalUrl =
    'https://v1.chaoxing.com/appInter/openPcApp?mappId=8056745';
  static const String gymReservationUrl =
    'https://reserve.chaoxing.com/front/web/apps/reservepc/index?reserveId=14191&fidEnc=a915b52ee0aa18ad';

  static const String changshaBusUrl = 'https://xlcxweb.busrise.cn/h5/mycs/#/';
  static const String schoolBusUrl = 'https://bus.jingzhixx.com/h5/';
  static const String lecturesUrl =
    'https://hd.chaoxing.com/hd/?marketId=18614&fidEnc=a915b52ee0aa18ad';

  static const String ehallUrl =
    'https://auth.chaoxing.com/connect/oauth2/authorize?appid=b90d1387d9ea42e7bba56450e6eb7087&redirect_uri=https%3A%2F%2Fehall.hunau.edu.cn%2Fmobile%2Findex.html%3Fuseragent%3Dchaoxing%26appId%3Db90d1387d9ea42e7bba56450e6eb7087%26appKey%3DI7JYq0kU87gKgF2b%26uid%3D22073114%26fidEnc%3Da915b52ee0aa18ad%26mappId%3D4311705%26formid%3D&response_type=code&scope=snsapi_base&state=128516';
  static const String libraryUrl =
    'https://auth.chaoxing.com/connect/oauth2/authorize?appid=a78d8ada07784074a6ae839eb187d649&redirect_uri=https%3A%2F%2Flibseat.hunau.edu.cn%2Fappindex.aspx%3Funitcode%3Dhunau%26appId%3Da78d8ada07784074a6ae839eb187d649%26appKey%3D6z2PCy8Jr1eAD72j%26uid%3D67661390%26fidEnc%3Da915b52ee0aa18ad%26formid%3Dnull%26mappId%3D8234750&response_type=code&scope=snsapi_base&state=128516';
  static const String campusCardUrl =
    'https://auth.chaoxing.com/connect/oauth2/authorize?appid=5f1cdbd2506748a8a1d7cbe737e40d32&redirect_uri=http%3A%2F%2Ffin-serv.hunau.edu.cn%2Fhomecx%2FopenCXOAuthPage%3Furltype%3D1%26appId%3D5f1cdbd2506748a8a1d7cbe737e40d32%26appKey%3D8VT2Ov83Vv12M8ZC%26uid%3D22073114%26fidEnc%3Da915b52ee0aa18ad%26mappId%3D4556968%26formid%3Dnull&response_type=code&scope=snsapi_base&state=128516';
  static const String paymentCodeUrl = campusCardUrl;
  static const String campusCardUA =
    'Mozilla/5.0 (Linux; Android 16; MEIZU 20 Build/BQ2A.251110.001-BP2A.250605.031.A3; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/147.0.7727.55 Mobile Safari/537.36 (device:MEIZU 20) Language/zh_CN com.chaoxing.mobile.hunannongyedaxue/ChaoXingStudy_1000257_5.3_android_phone_53_234 (Kalimdor)';

  static const String repairsBaseUrl = 'https://bxpt.hunau.edu.cn';
  static const String repairsIndexUrl = '$repairsBaseUrl/relax/mobile/index.html';
  static const String repairsSsoUrl =
    '$ssoLoginUrl?service=http%3A%2F%2Fbxpt.hunau.edu.cn%2Frelax%2Fsso%2Fcas%2Flogin';

  static const String storageUsernameKey = 'username';
  static const String storagePasswordKey = 'password';
  static const String storageTokenKey = 'token';
  static const String storageAuthStateKey = 'auth_state';

  static const String defaultSemester = '2025-2026-2';
  static const int primaryColorValue = 0xFF09C489;
}