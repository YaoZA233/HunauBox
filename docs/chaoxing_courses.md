# 学习通课程

入口为「功能 → 教务与学业 → 学习通课程」，也可在首页自定义快捷入口中添加。

复用应用已有超星 Cookie，通过 HTTPS 读取课程列表。课程按校园账号保存在本机；再次进入优先显示上次成功结果，主动刷新成功后更新，刷新失败保留旧结果。若应用的超星会话过期，点击「打开学习通 / 登录」，完成登录后返回，再手动刷新。

课程按课程 ID 与班级 ID 去重，读取「我学的课」及课程文件夹，支持课程名、教师、学校搜索与文件夹筛选。展示封面、教师、学校、开课时间和可用的任务点进度。点击卡片在应用 WebView 打开该课程。任务点进度缺失时显示未知，不视为 0%。「已结束课程」「已退课课程」属于学习通单独页面，本功能不合并它们。

## 接口依据

2026-11-01 检查用户提供的个人空间页面：`https://i.chaoxing.com/base` 是外壳，实际课程 iframe 位于 `mooc2-ans.chaoxing.com/mooc2-ans/visit/interaction`。网页内联脚本与公开的 `courseJobInfo.js` 提供以下读取接口：

- POST `/mooc2-ans/visit/courselistdata`：`courseType=1`，`courseFolderId=0` 为根目录，其他文件夹 ID 来自 `#fileList li[fileid]`；其余筛选参数读取 interaction 页隐藏字段。
- GET `/mooc2-ans/mycourse/stu-job-info`：`clazzPersonStr` 为卡片 `info` 字段的逗号拼接值，进度取 `jobArray` 的 `clazzId`、`jobFinishCount`、`jobCount`。
- 课程字段读取 `.learnCourse` 中的 `.course-name`、`.course-info`、`.course-cover`。课程地址保留网页返回的班级及访问参数，不硬编码用户或课程 ID。

接口属于网站内部接口，后续网页结构变更可能需要更新解析。列表返回无法识别内容或某个文件夹读取失败时显示错误，避免将失败当作空列表或完整结果。进度接口为补充信息，失败时保留课程列表。

## 验证

`flutter test --no-pub test/chaoxing_course_service_test.dart test/chaoxing_courses_page_test.dart`

覆盖卡片解析、文件夹遍历与去重、同课不同班级、登录过期、空列表与异常响应区分、进度失败降级、搜索和文件夹组合筛选、重试，以及手机横竖屏、平板、深浅主题和两倍字体。测试使用虚构课程与模拟响应；浏览器页面核实不等于设备端登录后端到端验证。
