# 校园 Agent

入口：右上角头像 → 设置 → Agent。默认关闭；开启后左侧依次显示“功能、通知、作业、Agent”，关闭时仅保留前三项。

在“模型服务配置”填写自己的 HTTPS 服务 URL、API Key 和模型名称。支持兼容 Chat Completions 的服务，模型需支持工具调用。URL 可为 Base URL（例如 `https://你的服务域名/v1`），也可为完整的 `/chat/completions` 地址。没有内置 Key、默认运营商或默认中转服务。

配置保存在设备安全存储中。保存或启用不会发起测试请求；只有发送消息才连接模型服务。对话及相应工具返回的校园数据将发送到所配置的服务，因此请使用可信服务商。校园登录密码、Cookie 和 OAuth 凭据不会作为工具结果发送。对话只保留在当前 Agent 页面，退出、清除或修改配置时重置。

当前接入课表查询与同步、作业查询及手动作业新增/完成、通知查询、成绩查询、校园卡余额、电费余额、学工问卷列表/题目、空教室查询，以及打开对应校园页面。

手动作业变更需要真实的界面确认，不能由模型通过 `confirmed=true` 绕过。学习通作业不能代交。充值、问卷提交和其他外部写操作在原页面中由用户完成，Agent 不自动创建支付订单或扣款。

关闭开关会停止正在进行的模型请求；已经完成的校园操作不会撤销。清除配置会关闭 Agent 并删除设备上的 Key。退出校园账号时同时清除 Agent 配置，避免后续账号沿用模型凭据。

实现 Chat Completions + 多轮 Function Calling。请求最多六轮，每轮最多八个工具；工具名称及参数严格校验。模型 HTTP 客户端独立于校园客户端，禁止携带校园 Cookie，且不跟随携带授权头的重定向。

测试：`flutter test --no-pub test/agent_service_test.dart test/agent_widget_test.dart`。离线界面预览：`flutter test --no-pub tool/agent_preview_test.dart`，结果位于 `build/agent_previews/`。上述检查不使用真实 API Key、不调用真实模型或支付接口。
