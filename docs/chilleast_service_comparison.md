# ChillEast 与本项目的教务、校园卡、电费访问方式对照

核对日期：2026-10-28。依据两个本地项目源码；未使用真实账户发起支付，未进行 23:00 后的同网实测。下文的性能差异是调用链分析，不是计时结果。

## 地址与协议

两者校园卡 OAuth 起始地址相同：`https://auth.chaoxing.com/connect/oauth2/authorize`，使用 `appid=5f1cdbd2506748a8a1d7cbe737e40d32`。完整 URL 见各自 AppConstants.campusCardUrl。回调为 `http://fin-serv.hunau.edu.cn/homecx/openCXOAuthPage`，随后到达 `homeCX/openHomePage` 获取 openid。不能保存临时 code 作为永久入口；业务请求依赖 openid 和 Cookie。

下表财务路径均位于 `https://fin-serv.hunau.edu.cn`。

| 功能 | 方法、路径 | 使用方式 |
| --- | --- | --- |
| 财务首页 | GET `/homeCX/openHomePage?openid=…&usertype=2` | 会话首页，必要时用于补充解析信息 |
| 付款码、卡片信息 | GET `/virtualcard/openVirtualcard?openid=…&displayflag=1&id=27` | 解析 HTML 中二维码、卡号、余额；ChillEast 优先用此路径取余额 |
| 校园卡充值页、卡片信息 | GET `/cardpay/openCardPay?openid=…&displayflag=1&id=28` | 当前项目优先用此路径取余额 |
| 支付宝校园卡充值 | POST `/alipay/transferFromAlipay2Card` | ChillEast 发送动态 AES datajson JSON，读取 resultData.htmlpost；当前项目发送 URL 编码表单并把响应当 HTML |
| 微信校园卡充值 | POST `/wxpay/transferFromWx2Card` | 两者均走动态 AES datajson，请求返回 H5 支付订单，再跳转微信 |
| 微信订单查询 | POST `/wxpay/queryWxWapPayStatus` | 查询支付状态 |
| 电费入口 | GET `/elepay/openElePay?openid=…&displayflag=1&id=30` | 初始化财务平台电费会话 |
| 校区 | POST `/channel/getXiaoQuList` | 动态 AES datajson；factorycode=E013 |
| 楼栋 | POST `/channel/queryBuildingList` | 动态 AES datajson |
| 房间 | POST `/channel/queryRoomList` | 动态 AES datajson |
| 电费余额 | POST `/channel/queryEleAccDetail` | 动态 AES datajson；传校区、楼栋、roomid、mertype、factorycode |
| 记录支付方式/宿舍 | POST `/myaccount/userlastbind` | 动态 AES datajson |
| 校园卡支付电费 | POST `/elepay/createPreThirdTrade` | 动态 AES datajson，payWay=2；不是银行卡/微信直接充值电费 |
| 校园卡账单入口 | GET `/selftrade/openQueryCardSelfTrade` | 带 openid 等参数建立查询环境 |
| 校园卡账单 | POST `/selftrade/queryCardSelfTradeList` | 动态 AES datajson |

本次没有发现 ChillEast 使用独立财务服务器或夜间备用充值域名。

## 教务

两者实际课表、成绩服务均使用移动教务的超星 OAuth：`https://auth.chaoxing.com/connect/oauth2/authorize`，appid 为 `ccf57937af7e40dcbdef0523e05e5ddd`，回调 `https://ydjwxt.hunau.edu.cn/njwhd/login/oauth2`。完整授权参数见 AppConstants.ydjwxtOAuthUrl。

- 课表：`https://ydjwxt.hunau.edu.cn/njwhd/student/curriculum`
- 学期：`https://ydjwxt.hunau.edu.cn/njwhd/semesterList`
- 成绩：`https://ydjwxt.hunau.edu.cn/njwhd/student/termGPA`
- 两者都用隐藏 WebView 获取 token，再用 HTTP 请求数据；缓存 token，通常按 JWT exp 判断过期，解析不了时按 3 小时处理，预留 5 分钟。

ChillEast 还定义旧教务 `http://jwxt.hunau.edu.cn/sso.jsp`、`/jsxsd/xskb/xskb_list.do`。当前项目对应旧教务常量是 WebVPN 包装地址。但本次检索未发现这些旧常量在实际页面/服务中的调用，不能根据常量断言当前教务页面更慢就是 WebVPN 引起。若“教务系统”指信息门户中的网页应用，其最终动态跳转 URL 还需要运行时导航记录确认。

ChillEast 信息门户入口：`https://portal.hunau.edu.cn/ydd/microService2/toApps2`。

## 明确的实现差异

1. 财务授权：ChillEast 用 Dio 手动逐跳跟随 302，最多 10 跳，直接提取 openid；当前项目启动 HeadlessInAppWebView，等待目标首页 onLoadStop，再同步多域 Cookie，授权等待上限 30 秒。后者多了 WebView 启动、页面加载和原生 Cookie 同步成本；目标导航失败时可能等到超时。
2. 余额来源：ChillEast 的 fetchRechargeInfo 优先调用 fetchPaymentCode；付款码有 55 秒缓存，卡片信息持久化到 SharedPreferences。当前项目先请求 openCardPay，解析不到再请求首页、付款码，必要时重新授权重试，可能形成更长的串行链。
3. 首屏：ChillEast 校园卡充值页先显示已有余额，后台刷新；静默刷新失败保留旧内容。当前项目每次进入显示 loading，等 fetchRechargeInfo 返回。
4. 并发：ChillEast 合并正在进行的校园卡信息请求，以及电费认证请求。当前财务服务没有对应的在途 Future 合并。当前概览并行加载校园卡、两个宿舍电费、最近账单等，冷启动时可能同时触发多个财务授权/信息查询。页面自身刷新合并不能替代跨服务认证合并。
5. 电费：ChillEast 仍然串行加载校区、楼栋和房间，不是所有数据都并行；但有持久化余额，列表完成后可先显示缓存并后台更新余额。当前项目还要等待余额查询才结束初始化，概览刷新时也会先清空对应电费余额。
6. 支付宝协议：两者 URL 相同但请求和响应协议不同。这值得单独核验、统一，不能仅换 URL，也不能据此推断所有夜间故障都由它引起。

## 23:00 后失败：能够与不能确定的内容

相关财务服务中未发现按 23 点禁止访问的本地条件，也未发现 ChillEast 切换夜间服务的实现。

可以确定：ChillEast 的缓存保留策略会让网络刷新失败时页面仍显示余额。因此“余额还能显示”不等于“此时能获取最新余额”，也不等于“充值能成功”。

尚不能确定：夜间失败究竟发生于超星 OAuth、fin-serv 会话入口、卡充值页、余额接口还是支付端；是否涉及服务结算/维护、网络环境或访问限制，必须有实际响应支持。不能把 23 点作为已确认的学校停服时间。

定位应在同设备、同网络、23 点前后对照：记录每一跳状态码、最终主机/路径、耗时、错误页类型和实际刷新时间；对比 openCardPay 与 openVirtualcard，以及 queryEleAccDetail。日志应隐去 Cookie、openid、用户信息和订单参数。充值是否成功以真实订单查询结果为准，不能靠缓存推断。

## 建议实施顺序

1. 把财务授权改成共享的纯 HTTP 流程，并合并并发认证/信息请求，保留现有正确的 Cookie 域隔离规则。
2. 余额先显示缓存、后台刷新，展示上次更新时间与刷新失败状态；房间切换不能串用旧宿舍余额，账户切换需隔离/清理缓存。
3. 已保存宿舍按 roomid 等信息直接请求余额，把校区/楼栋/房间完整列表延迟到编辑选择时加载。
4. 只对确认的会话失效重新认证，避免解析错误或业务停服时反复授权；增加分阶段耗时和脱敏诊断。
5. 单独核验支付宝动态 AES 协议；下单流程需单独验证，不把可能产生重复订单的请求纳入通用自动重试。

上述对照反映优化前的状态。

## 已实施的优化

- 财务 OAuth 改为共享 HTTP 跳转流程，等待最终首页和 Cookie 写入后才接受 openid；授权设总时限并取消超时请求。复用在途授权、校园卡余额、付款码和同一宿舍电费请求。
- 校园卡余额优先从 openVirtualcard 解析，必要时再尝试 openCardPay。仅识别到会话失效时重新授权，普通超时或解析失败不重复登录。
- 校园卡、电费余额快照按登录账号隔离；宿舍快照键包含校区、楼栋、房间和电表类型。快照不保存 openid，不用于证明支付会话有效。
- 概览和充值页保留已有余额、后台更新；充值页显示更新时间，更新失败明确提示上次余额。已保存宿舍进入页面直接查余额，点击“更换房间”后才加载选择列表。
- 支付宝下单对齐动态 AES JSON 和 resultData.htmlpost；微信、支付宝、电费下单均不因网络错误自动重放，阻止同类并发提交。下单前的只读校验仍使用网络响应。
- 退出时等待在途财务读取完成并清空内存会话，清除两个槽位的宿舍选择；持久化余额按账号隔离。
- 校园卡网页入口把 HTTP Cookie 同步至 WebView，复用已建立的财务会话。教务的 OAuth/token 接口保持现有实现，本次没有证据支持更换其服务地址。

验证：136 项相关测试通过；Flutter 资源与 Dart 内核构建通过。Android APK 构建受本机 Java `Unable to establish loopback connection` 阻碍；未生成可交付的新 APK。未进行真实付款和 23:00 后同网实测，不能据此保证学校夜间业务可用。
