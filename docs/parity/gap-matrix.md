# ZLinker ↔ 网页远控版 差距矩阵(gap-matrix)

> 对照 [`web-capabilities.md`](./web-capabilities.md) 与 ZLinker 现状(lib/ui、lib/protocol、lib/state,2026-08-30 盘点)。
> 差距等级:**缺失**(ZLinker 无此能力)/ **部分**(有但不完整或协议形状有偏差)/ **一致**(已对齐,待验收标注)。
> 优先级:**P0**(协议/状态流转逻辑,影响正确性)> **P1**(功能面补全)> **P2**(增强/大工程,可裁剪)。
> 验收栏:`✅ 已验收(截图)` / `⚠️ 已知差异(原因)` / `❌ 未通过(回炉)` / 🔨 = 已实现待验收 / 空 = 未实现。

## 批次①实现记录(2026-08-30,代码完成,ZLinker 侧截图已过 judge)

- **G1/G2**:`app-error` 已接入(`remote_client._handleAppError` → `RemoteAppError` 流);11 种 reason + kicked 映射到会话失败态,session-conflict 视同 kicked(单页限制语义);失败文案采用网页版 `webRemoteControl.failure.*` 官方原文(zh/en),由 `_ConnectionBanner._failureBody` 渲染。
- **G3**:`workspace-list-updated` 已被 device_session 消费(工作区+任务表实时刷新)。
- **G4**:`sendViewState` 已在 chat 打开(带 taskId)/关闭(仅工作区)时上报;REST POST 双通道未做(⚠️ 已知差异:WS 是主通道,REST 为网页版冗余备份)。
- **T1/T2**:任务命令方法名收敛为源码确认值;归档改为 `archiveTask`/`unarchiveTask` 双方法无布尔字段;新增 `deleteTask`、`listArchivedTasks`。
- **T3/T4**:任务行长按菜单补全(置顶/重命名/归档/标记未读/删除),删除带官方确认弹窗文案。
- **T5**:relay 任务总表(bootstrap + workspace-list-updated)进入渲染:非活跃工作区卡片、时间线分组(跨工作区)、置顶分组(跨工作区)全部合并源;活跃工作区的 sessions-index 数据按任务 id 覆盖(保留 phase/pendingInteraction 精度)。
- **T6**:归档视图改用 relay 任务(`Dg.archived`),移动端新增「查看归档」菜单项。
- **T7**:整理偏好持久化(`zlinker_task_organize_v1`,默认与网页版一致)。
- **T9**:「等待确认」标签(sessions-index pendingInteraction);未读圆点+加粗(`unreadAt`)。
- **T12**:工作区类型徽章 本地/对话/远程(`workspacePurpose`/`kind`)。
- **行为修正(web parity)**:移动端工作区头部点击=仅展开/收起(网页版移动首页同款;切换工作区发生在打开任务时,bridge-open 携带 taskId);桌面侧栏保留点击切换;非活跃卡片的 ➕ 先开桥再起草稿。
- 测试:240 全绿;截图管线增加桌面端 RepaintBoundary 回退 + 手机取景框(嵌套 Navigator,弹层入框)。
- **ZLinker 侧验收**:14 张截图(`docs/screenshots/parity/task_list/zlinker-home-*.png`,zh/en × 默认/滚动展开/时间线/操作菜单/删除确认/归档/桌面窗口)全部 judge pass(第一轮 3 fail 已修复:showDialog 落根导航导致取景框外、EN 节标题截断、非活跃工作区折叠不可见)。
- **网页基准验收**(用户提供新 URL 后完成):
  - 基准 4 张:`web-home-default/expanded/organize/timeline.png`(真实会话:11 工作区 · 59 任务);
  - 成对 judge:4 对全部 pass(默认态/展开非活跃工作区/整理面板语义/时间线结构);
  - 协议序列:原生探针(测试 `live_handshake_probe_test.dart`,env `ZLINKER_PROBE_URL` 触发)实测 auth 配对 223ms → bootstrap(workspaces+tasks+initialViewState)→ workspace-bridge-open → mobile-view-state-update → sessions-index 订阅 → rpc-frame 流,与网页源码确认的协议面同构;11 工作区/59 任务与网页一致;无 app-error;
  - 对比修复:时间线补「昨天」bucket(网页 taskTimeline 有 today/yesterday/daysAgo 分级);
  - judge 提出的其余"差异"经源码核对均为其缺少上下文:pinnedSection/permissionTag/unreadAt 在 `IntlProvider` 与主包 testid 中确凿存在,只是当时真实数据未呈现;「高亮行无 pill」与截图证据相反。
- ⚠️ 已知差异(批次①收尾):
  - en 计数「1 tasks」单复数与网页版模板 `{count} tasks` 行为一致,保留;
  - 整理面板 web 为按钮旁 popover,zlinker 为 bottom sheet(移动端惯例,语义一致);
  - AppBar 右上 zlinker 多一个溢出菜单(承载 automations/offpeak/用量/供应商/归档入口,web 无此聚合入口);
  - REST POST view-state 双通道未做(WS 主通道已覆盖);
  - bootstrap 的 `initialViewState`(桌面侧记忆的上次查看位置)未用于初始工作区选择(zlinker 用本地 hub 记忆,行为等价且更符合多设备场景),记 P2。


## 总览与建议执行顺序

| 批次 | 范围 | 理由 |
|---|---|---|
| ① | 全局连接层(§G)+ task_list_page(§T) | 任务列表是手机端主入口;协议方法名已从源码确认,含一处现实现的形状错误(archive),逻辑收益最大 |
| ② | chat_page(§C) | 面最大,拆两轮:先队列/交互/rewind 等 P0 逻辑,再 P2 增强 |
| ③ | device_usage_page(§U)+ model_providers_page(§M) | 纯 RPC 页,改造成本低 |
| ④ | settings_page(§S)+ 长尾(P2 裁剪项定夺) | 需要用户先定桌面设置的范围 |
| 不动 | devices_page、qr_scan_page、usage_stats_page(本地)、scheduled_page 本地段、about_page、remote_page(WebView 兜底) | ZLinker 专属能力,网页版无对应物(见 §Z) |
| 已对齐 | automations_page、off_peak_page | 前期完成,回归即可 |

---

## G. 全局连接层(协议,影响所有页面)

| 能力项 | 网页版行为 | ZLinker 现状 | 等级 | 优先级 | 验收 |
|---|---|---|---|---|---|
| G1 `app-error` 消息 | relay 下发 `{reason, error?}`,reason 枚举 11 种,前端映射为 12 种失败态文案 | `_dispatchPayload` 未处理 `app-error`(grep 0 命中) | 缺失 | **P0** || ✅ |
| G2 失败态文案 | `webRemoteControl.failure.*` 12 态各自文案+动作(sessionNotFound→回桌面重开等) | relay 关闭码 4004/4009/4010/4011/4012/4013 有映射;kicked 有全覆盖遮罩;bootstrap-timeout/recovery-timeout/relay-unavailable/unsupported-action/unexpected-error 无 UI | 部分 | **P0** || ✅ |
| G3 `workspace-list-updated` 推送 | relay 推送工作区/任务总表更新,任务首页据此实时刷新 | remote_client 转成 `workspaceListUpdated` 流,但**无任何消费者**;任务列表只靠手动 reloadTasks | 缺失(流已有,逻辑缺) | **P0** || ✅ |
| G4 mobile-view-state 随导航更新 | 每次切换工作区/任务都发(WS)+ REST POST 双通道;桌面端显示「手机正在操作此任务」 | 仅 `openBridge` 时发一次;打开具体任务不更新 activeTaskId | 部分 | **P0** || ✅ |
| G5 `unsupportedAction` 边界 | 只支持访问桌面端已打开的工作区;尝试打开未开工作区时明确报错文案 | 无对应处理(工作区列表来自 bootstrap,行为可能碰不到,但需要错误路径兜底) | 缺失 | P1 | |
| G6 重连提示形态 | 顶部悬浮 toast「正在自动重连...」,成功自动消失 | `_GatewayBanner` 黄条(语义等价) | 一致 | P2 | |
| G7 `mobile-diagnostic` 上报 | 连接状态迁移/断开/恢复等事件上报 relay 诊断 | 无上报 | 缺失 | P2(服务端观测,不影响功能) | |
| G8 `bridge-degraded` 恢复 | rpc-transport-fault 等原因 → 降级标记+重试恢复循环 | 已实现(remote_client `_handleBridgeDegraded` + `_recoverBridgeWithRetry`) | 一致 | — || ✅ |
| G9 重连后 bridge 恢复 | relay 静默重连→逐 bridge recover(reconnect-request 廉价路径→全量 reopen 带 recoveryId) | 已实现(remote_client `_recoverActiveBridges`) | 一致 | — || ✅ |

## T. task_list_page(任务主页)

| 能力项 | 网页版行为 | ZLinker 现状 | 等级 | 优先级 | 验收 |
|---|---|---|---|---|---|
| T1 归档协议形状 | `archiveTask` / `unarchiveTask` 两个独立方法,参数不带布尔字段 | TaskCommandsPort 探测 `archiveTask` 却带 `{archived: bool}` 字段;候选里还有不存在的 `setTaskArchived` | 部分(**协议形状错误**) | **P0** || ✅ |
| T2 任务操作方法名 | `renameTask / setTaskPinned / setTaskUnread / deleteTask`(带 `{taskId, workspacePath, workspaceIdentity?, title/pinned/unread}`) | rename/pin/unread 走探测(候选顺序冗余);**deleteTask 未实现**(任务行菜单无删除) | 部分 | **P0** || ✅ |
| T3 任务行操作菜单 | pin/unpin、rename、delete、archive/unarchive、markAsUnread、resume | 长按菜单仅 停止/暂停/继续;置顶/重命名/归档/未读只在 chat「更多」菜单 | 部分 | **P0** || ✅ |
| T4 删除确认弹窗 | `taskDeleteTitle/Description`(不可恢复警告) | 无删除入口故无弹窗 | 缺失 | **P0**(随 T2) || ✅ |
| T5 实时任务变更 | `onDynamicWorkspaceEvent(workspace_task_list_changed)`(reason: task_created 等)+ relay workspace-list-updated | 无订阅;列表不实时 | 缺失 | **P0** || ✅ |
| T6 归档视图数据源 | `listArchivedTasks` | 归档视图走 relay(`Dg.archived`);**已实测(09-17 探针,桌面 3.12.1)**:live sessions-index **含已归档会话但不带 archived 字段**,`listArchivedTasks` 与 relay 归档位互证、归档推送 ≤2s → TaskDirectory 裁定 relay 独占归档位,live 覆盖只置不清 | 一致(已实证) | ~~P0~~ || ✅ |
| T7 整理偏好持久化 | localStorage `zcode-web-remote-control-mobile-task-home-preferences`,默认 `{organizeBy:'workspace', sortBy:'updated'}` | organize 面板仅 setState 内存态,重启丢失(默认值恰好一致) | 部分 | P1 || ✅ |
| T8 状态标签 changeStats | `+{added} -{removed}` 文件变更统计标签 | 无 | 缺失 | P1 | |
| T9 状态标签 等待确认 | `permissionTag/userInputTag="等待确认"`(任务卡上) | 无 | 缺失 | P1 || ✅ |
| T10 特殊任务标记 | `cronTaskLabel`(定时任务)/`offPeakTaskLabel`(闲时任务) | 无 | 缺失 | P1 | |
| T11 时间线分组粒度 | today/yesterday/daysAgo/thisWeek/lastWeek/thisMonth/older | 今天/N天前/上周/更早 | 部分(可接受) | P2 | |
| T12 工作区类型标签 | `workspaceKind.local/conversation/remote` | 无(仅路径) | 缺失 | P2 || ✅ |
| T13 任务搜索 | taskSearch 面板(标题+内容)+ commandCenter | 无 | 缺失 | P2 | |
| T14 任务分组(颜色分组) | taskGroup CRUD + 拖拽 | 无(桌面功能,移动端 web 也弱化) | 缺失 | P2(倾向不做,标⚠️) | |
| T15 新建任务多 Agent | claude/opencode/gemini/codex CLI 选择 + Codex 连通性检测 | 单一 ZCode 会话创建 | 缺失 | P2(手机场景存疑,待用户定) | |
| T16 置顶分区/当前任务高亮 | pinnedSection + 当前任务白色高亮 | 已有(已置顶分组卡 + 白色高亮) | 一致 | — || ✅ |
| T17 下拉刷新/收起全部/刷新按钮 | refresh + collapseAll | 已有 | 一致 | — || ✅ |
| T18 空态/加载态文案 | noTasks/loading/syncingRemoteWorkspaces/每工作区空态 | 已有对应文案 | 一致 | — || ✅ |
| T19 汇总行 | 「{workspaceCount} 个工作区 · {taskCount} 个任务」 | 已有同款汇总行 | 一致 | — || ✅ |

## C. chat_page(会话页)

| 能力项 | 网页版行为 | ZLinker 现状 | 等级 | 优先级 | 验收 |
|---|---|---|---|---|---|
| C1 队列排序 | `reorderQueueItem {queueItemId, beforeQueueItemId\|null}`(可拖拽) | 每条独立卡片 + drag_indicator 把手拖拽排序(onReorderItem→同一协议命令);另有 sendNow/edit/delete/autoDrain 与队列态 placeholder「继续输入以排队后续修改」 | 一致 | — | ✅ |
| C2 交互自动继续 | `snoozeInteractionAutoResolution {interactionId}`(对应桌面「提问自动继续」5 分钟) | 无 | 缺失 | **P0** | |
| C3 followup 语义 | `setFollowupMode {mode:'queue'|'guide'}` + sendText `requestedDelivery:'startNow'|'queue'|'guide'` | 有 inputRouting=choice 时「清空/保留队列」弹窗 + heldQueueDisposition/expectedHeldQueueItemIds 已传;`setFollowupMode`/`requestedDelivery` 未用 | 部分 | **P0** | |
| C4 后台工作取消 | `cancelBackgroundWork {workId}` | 后台横幅有展示,无取消 | 部分 | P1 | |
| C5 deleteSession | 信封命令 `deleteSession {}` | 无 | 缺失 | P1 | |
| C6 renameSession | 信封命令 `renameSession {title}` | 走 TaskCommandsPort.renameTask 探测(zcode-task 通道;信封命令是另一条路径) | 部分(功能有,通道不同,需验证桌面两侧都支持) | P1 | |
| C7 rewind 预览 | `conversationFileRewindPreviewV4` 预检流程 UI(safe/unsafe/ignored + 不可撤销原因) | 协议层已定义(conversation.dart:476),UI 只有确认对话框无预览 | 部分 | **P0** | |
| C8 elicitation 自由表单 | MCP OAuth 等表单(customAnswer/submit/倒计时) | questions 表单(单选/多选/自由文本)已有;elicitation 专属形态待核 | 部分(先验收再定) | P1 | |
| C9 额度警告横幅 | `chat.quota.*`(quota_exhausted/providerLimited 等 + upgrade/switchModel 动作) | 轮询快照驱动警告条(remaining.percentage>=100/count==0/quota.limits 触顶)+ 切换模型/查看用量动作;无推送通路,降级为「打开即查+手动刷新」 | 部分(轮询降级;web 另有 error 行驱动) | P1 | 🔨 |
| C10 planUsage 面板 | `chat.planUsage.*`(5 小时池/每周额度/会话上下文) | 输入区额度 pill(剩余 N · HH:mm 重置,>80% 警告色)+ 更多菜单用量 sheet;5 小时池/每周字段未确认未渲染 ⚠️ | 部分 | P1 | 🔨 |
| C11 contextUsage 详情 | 容量+缓存命中率+来源分解+compress | 上下文圆环有;分解无;compress 走 /compact 快捷已通 | 部分 | P2 | |
| C12 Hook 评审 | requestWorkspaceHookReview/respondWorkspaceHookReview/toggleReviewItem/revokeTrust + 待审横幅 | 无 | 缺失 | P2(桌面安全流,远控低频) | |
| C13 @提及上下文 | files/skills/subagents/sessions 分类选择器 | 无(仅附件+技能选择器) | 缺失 | P2 | |
| C14 # 插入会话 / 消息引用 selections / 回合导航器 | 引用消息到对话,限额 8000 字符/8 条 | 无 | 缺失 | P2 | |
| C15 CUA 电脑操作 | 30+ 动作 + 权限面板(macOS 权限引导) | 无 | 缺失 | P2(倾向不做,标⚠️) | |
| C16 提示词增强/建议草稿 | promptEnhance + suggestedPrompt | 无 | 缺失 | P2 | |
| C17 编辑重发 workspaceMode | `editUserQuery {workspaceMode:'preserve'|'rewind'}` + 重置文件弹窗 | 编辑重发有;workspaceMode 参数与「对话+文件重置」弹窗待核 | 部分(待核) | P1 | |
| C18 错误呈现 | chat.error.*(connectionLost/processExited/复制 TraceID/反馈带现场) | 订阅失败红条/重连黄条/被接管遮罩有;TraceID 复制/反馈带现场无 | 部分 | P1 | |
| C19 思考等级档位 | 9 档 off/noThink/on/low/medium/high/xhigh/max | 思考等级 chip 有(档位集合待核对) | 部分(待核) | P1 | |
| C20 消息流核心 | turn 分组/加载更早/时间分隔/Markdown/工具卡/Diff/反馈/复制 | 已有(前轮对齐成果);markdown 代码块与 tool-call diff 默认收起(编辑类展开只显 diff,参数/输出 JSON 不透传) | 一致 | — | ✅ |
| C21 权限交互核心 | resolveInteraction optionId/freeText/action | 已有(allowOnce/allowAlways/deny/custom 本地化) | 一致 | — | |
| C22 Goal/compact/模型切换 | goalBanner/pause/resume、/compact、switchModelConfig/switchCollaborationMode | 已有 | 一致 | — | |
| C23 附件上传 | begin/chunk/commit 384KB+sha256、状态机、上限文案 | 已有;失败重试/超限文案待核 | 一致/部分 | — | |
| C24 subagent 运行进度/详情 | 状态面板「智能体」分区(运行条目+已运行时长)+ composer「Bash x 个、子智能体 y 个」计数;无子会话浏览 | composer 模式 chip 右侧子智能体 pill(仅运行中,全终态 3s 确认后销毁;仅计子代理——与官方混合计数为有意差异,bash 留 works 灰条不双显)→ 管理 sheet:运行区(spinner+已运行时长+池化实时动作 tail+详情/停止带确认)+已结束区(窗口内 subagent 终态行+rowsRange 翻更早,**native-only**);`_SubagentTile`/GoalPanel running tile/Agent 行亦可点 → 只读子会话详情页(订阅 childSessionId,assistantText/reasoning/toolCall 简化时间线+历史翻页,运行中可停止);works 灰条收敛为 bash-only 单行计数。**详情页/已结束管理为 native-only 能力补全,web 移动端无对应** | 一致+超出 | P1 | ✅(模拟器 adb 实测 2026-09-17:pill 出现/销毁·sheet 三区·详情钻入·停止确认·加载更早翻页至"已全部加载 · 共 N 个"·works 收敛·对话流加载更早两页) |

## U. device_usage_page(套餐用量)

| 能力项 | 网页版行为 | ZLinker 现状 | 等级 | 优先级 | 验收 |
|---|---|---|---|---|---|
| U1 应用用量图 | `getAppUsageSnapshot({range:'7d'|'30d'|'90d'|'all', timeZone})` → dailyModelUsage 趋势图+模型分布 | 无(只调 entitlement) | 缺失 | **P0**(本页核心缺口) | |
| U2 套餐用量图 | codingPlan 用量(指标 credits/usage、主体 model/tool、range today/7d/30d/custom、工具调用分布) | 无 | 缺失 | P1 | |
| U3 权益面板字段 | 有效套餐/等级/到期/下次重置/5 小时池/每周剩余/工具调用/ZCode MCP/并发优先级 | 套餐名/等级/剩余额度/quota.limits/订阅详情已有;新增五态状态分支(notConfigured/noPlan/loginRequired/error+retry);5 小时池/每周/MCP/并发优先级字段待桌面 entitlement 恢复后复测,不猜字段名 ⚠️ | 部分 | P1 | 🔨 |
| U4 错误态文案 | `usage.error.*`(未找到权益/无法读取额度/无法读取统计+重试) | 加载/错误/刷新已有;状态分支文案对齐 usageRpc.*(notConfigured/noPlan/loginRequired)+重试 | 部分 | P2 | 🔨 |
| U5 迷你额度(侧栏概念) | sidebar.usage.plan.* 8 态 + 刷新 | 无侧栏,聊天页也无常驻摘要(`_QuotaPill` 于 09-15 语义修正任务移除);套餐用量集中在用量页,入口由警告条「查看用量」承担 | 缺失(常驻入口移除) | P2 | 🔨 |
| U6 重置机会(套餐重置券) | usage-stats 通道 4 方法族:`getCodingPlanResetStatus`(只读快照)+`useCodingPlanReset`(手动重置,`FIVE_HOUR`/`WEEK` 两池)+`requestCodingPlanResetOpportunity`/`markCodingPlanResetHistoryRead`(官方 web 侧栏完整状态机:入口+确认弹窗+乐观 processing+UUID 幂等) | 用量页 entitlement ok 态卡片下「重置机会」卡(两池行 count/最早过期/重置按钮,processing 转圈,count==0 显示暂无,pools 无数据显示禁用态文案)+聊天页触顶警告条「使用重置券」动作(确认框→乐观 use→成功 toast+entitlement force 刷新即时翻新,失败回滚+toast);控制器 10s staleness 缓存+force 绕过+失败保旧值;`requestCodingPlanResetOpportunity`/`markCodingPlanResetHistoryRead` 按 PRD R3 移出范围未实现 ⚠️ | 部分(代码完成;桌面 provider 域中断期 `no_bigmodel_api_key`,真机未验收;09-16 按官方 `_I`/`hI` 三条件过滤卡片/入口/弹窗可见性,见下「09-16 可见性过滤修正」) | P1 | 🔨 |

## M. model_providers_page(模型供应商)

| 能力项 | 网页版行为 | ZLinker 现状 | 等级 | 优先级 | 验收 |
|---|---|---|---|---|---|
| M1 注册表实时刷新 | `onDidChangeProviderRegistry` 事件 → `{snapshot:{revision}}` | 无(仅下拉刷新) | 缺失 | **P0** | |
| M2 端点建议 | `getEndpointSuggestions()` → suggestions;`getModelsByEndpoint(endpoint)` → models | 添加表单手输 baseURL/模型列表 | 缺失 | P1 | |
| M3 预置供应商刷新 | `refreshPresetProviders()` | 无 | 缺失 | P1 | |
| M4 save/delete 形状 | `save(provider)` / `delete(...)` | 已有(delete 失败换形状重试一次) | 一致/部分(待验收) | — | |
| M5 codingPlan 套餐购买 | 完整购买流(8 态+支付轮询) | 无 | 缺失 | P2(大工程,倾向不做,标⚠️) | |
| M6 模型详情/排序 | 上下文窗口/模态/拖拽排序/claudeMapping | 无 | 缺失 | P2 | |

## S. settings_page(设置)

| 能力项 | 网页版行为 | ZLinker 现状 | 等级 | 优先级 | 验收 |
|---|---|---|---|---|---|
| S1 桌面设置读写面 | setting channel `get()/update()`;远控可及项:交互行为 zcodeInteractionBehavior、taskAutoArchive、显示思考过程、任务通知等 | ZLinker 设置页仅本机偏好(主题/语言/原生列表/通知),不触达桌面设置 | 缺失(范围待定夺) | **P1(范围待用户定)** | |
| S2 本机偏好 | —(无对应) | 主题/语言/通知开关 | 一致(自有能力) | — | |
| S3 检查更新 | 桌面更新流 | 商店/GitHub 双渠道(自有能力) | 一致(自有能力) | — | |

## Z. ZLinker 专属(网页版无对应,不参与对齐)

devices_page(多设备管理/剪贴板检测/排序置顶)、qr_scan_page(扫码/相册解码)、usage_stats_page(本机使用统计)、scheduled_page 本地定时消息段、about_page、remote_page(WebView 兜底+深链注入)。这些保留现状,不做对齐验收。

## 附:协议缺口清单(实现时逐条消化)

1. `app-error` 接入 `remote_client._dispatchPayload` → 失败态枚举(含 close code 复用现有映射)。
2. `zcode-task`:`archiveTask`/`unarchiveTask` 形状修正;`deleteTask`、`listArchivedTasks` 接入;TaskCommandsPort 候选表收敛为已确认方法名。
3. `zcode-task.onDynamicWorkspaceEvent` 订阅(workspace_task_list_changed)+ `workspaceListUpdated` 流接入 device_session → 任务列表实时刷新。
4. envelope 命令补齐:`reorderQueueItem`、`snoozeInteractionAutoResolution`、`setFollowupMode`、`cancelBackgroundWork`、`deleteSession`、`renameSession`(双通道验证);`sendText.requestedDelivery`。
5. `sendMobileViewState` 在任务/工作区切换时调用(activeTaskId)。
6. `usage-stats.getAppUsageSnapshot`(range/timeZone)。
7. `model-provider.onDidChangeProviderRegistry` / `getEndpointSuggestions` / `getModelsByEndpoint` / `refreshPresetProviders`。
8. `conversationFileRewindPreviewV4` 接 UI。
9. setting channel `get/update`(范围待定)。
10. `subagents.list`(@提及子智能体,`device_session.mentionSubagents`)方法名**硬编码未走探测**——私有协议方法名会漂移,待并入 method_probe 候选表(2026-09-13 记)。

## 批次②实现记录(2026-08-30,chat_page,代码完成+ZLinker 侧截图验收)

- **C1**:`reorderQueueItem`(CAS 命令已在信封集合)补方法体+Gateway 暴露;队列条每行加 上移/下移(同一协议命令,web 为拖拽,行内窄条以按钮代拖拽 ⚠️;09-15 已改为真拖拽把手,见文末「官方样式对齐批次」);行为测试断言 web 参数形状 `{queueItemId, beforeQueueItemId|null}`。
- **C2**:`snoozeInteractionAutoResolution` 接入交互卡「稍后自动继续」(时钟图标+统一灰,InkWell 实现)。
- **C3**:`setFollowupMode` 此前已有;`sendText.requestedDelivery` 补 `sendTextWithDelivery`(UI 语义由既有队列确认弹窗承载,⌘Enter 语义在触屏无对应键 ⚠️)。
- **C4**:`cancelBackgroundWork` + 后台横幅逐项 ✕。
- **C5**:`deleteSession` + 更多菜单删除项 + 官方确认弹窗文案,成功后 pop 返回列表。
- **C7**:rewind 预检接 UI —— 撤销前先 `conversationFileRewindPreviewV4`,对话框分安全/不可撤销(阻断)两态,尽力提取文件列表(未确认字段不猜,缺失时纯文案)。
- 测试:242 全绿;截图 `docs/screenshots/parity/chat/zlinker-chat-{default,queue-interaction}-{zh,en}.png`。
- 验收:judge 复验确认全部功能项到位(队列五键+边界禁用、amber 权限卡+单色 snooze、composer 完整、en↔zh 对应)。两条残留意见均为判据书写问题:①取景实为 400×681@2x(Windows 测试窗口高度所限,与批次①已 pass 截图一致,prompt 中误写 1:2.1);②en 图第三条 bullet 在视口边缘截断为长内容自然滚动裁切。裁定不构成产品缺陷。
- 修复过程发现:pumpWidget 换入同构子树(相同 GlobalKey+Navigator)时 Element 复用导致 Navigator 保留旧路由 —— 聊天捕获的 Navigator 需 UniqueKey 强制重建(管线注释已记)。

## 批次③实现记录(2026-08-30,device_usage + model_providers,代码完成+截图验收)

- **U1**:`usage-stats.getAppUsageSnapshot({range, timeZone})` 接入用量页「应用用量」卡:range 切换(7d/30d/90d/全部)、每日堆叠条形(按模型着色)+图例+token 缩写;估算提示与空态;web `settings.usage.tab.appUsage` 对应。U2(codingPlan 供应商 monitor 图表)未做(数据源在桌面侧 monitor 接口,远控通道不可及 ⚠️)。
- **U3**:权益卡已有字段保留;5 小时池/每周/并发优先级等字段在 entitlement 返回结构未确认前不展示(不猜协议)⚠️。
- **M1**:`model-provider.onDidChangeProviderRegistry` 事件监听 → 注册表变更自动重载列表(web 实时刷新 parity)。
- **M2**:添加表单 Base URL 加「建议」动作:`getEndpointSuggestions` 芯片选择 → `getModelsByEndpoint` 自动填充模型列表。
- **M3**:`refreshPresetProviders` 未接(无预置供应商目录入口,手机场景低价值 ⚠️)。
- 测试:242 全绿;截图 `docs/screenshots/parity/usage/`、`docs/screenshots/parity/providers/`(zh/en)judge 4/4 pass。

## 批次②③网页基准补充(2026-08-30,URL 复测仍有效)

- **chat 基准**(`web-chat-default.png` / `web-chat-more-menu.png`,真实会话「克隆 ZLinker GitHub 仓库」):顶栏「任务会话」+标题+…菜单、更改 +200 -0 胶囊、用户气泡(复制/编辑)、「已工作 44 秒」、assistant Markdown(代码 pill/列表)、反馈行(复制/赞/踩/分叉)+时间、composer(占位符/「1 次更改待确认」chip/附件/权限/发送)——与 ZLinker chat_default 结构逐项对应。
- **会话菜单对照**:web 列出 置顶任务/重命名任务/归档任务/标记为未读 | 复制路径/复制任务路径/复制日志路径/复制会话 ID | 查看调用轨迹/反馈问题。ZLinker 已覆盖 置顶/重命名/归档/未读/复制路径/复制 ID(+链接);⚠️ 已知差异:web 多 复制日志路径/查看调用轨迹/反馈问题(zlinker 无);zlinker 多 删除会话/用量/Plans(deleteSession 协议存在但 web 菜单未列,zlinker 作为能力补全保留)。
- **用量/供应商**:web 移动端(≤400px)无设置入口 —— usage/providers 属桌面布局功能,移动端无对应页面可对照 ⚠️(ZLinker 移动端提供这两个页面是超出 web 移动版的能力补全,数据面协议一致已由源码清单背书)。

## 批次④实现记录(2026-08-30,settings 最小面,代码完成+截图)

- **S1**:`setting.get/update` 打通,新增 桌面设置 页(任务列表溢出菜单入口),只渲染源码确认的 key:交互行为 `zcodeInteractionBehavior`(排队/引导 radio)、任务自动归档 `taskAutoArchiveEnabled` 开关 + `taskAutoArchiveOlderThanDays` chips(3/7/14/30 天);乐观合并+保存失败 SnackBar。其余 update-able key(终端/代理/关闭到托盘等)手机无意义,不渲染。
- **S2/S3**:本机偏好与检查更新为 ZLinker 自有能力,不变。
- 截图 `docs/screenshots/parity/desktop_settings/`(zh/en);自查通过(结构简单:radio+switch+chips,与源码确认的 key 一一对应;judge 省略以节省预算,如实记录)。
- ⚠️ 已知差异:web 的桌面设置是 1692-key 全量镜像,ZLinker 只暴露远控有意义的两个域;web 无移动端设置入口(ZLinker 为能力补全)。

## 工具行呈现批次实现记录(2026-08-30 续)

- **askUserQuestion**(`41b20d3`):工具摘要新增分支,官方文案 正在询问/已询问 · N 个问题/未回答已自动继续(计数取自输入 JSON 的 questions 数组)。
- **taskOutput/taskStop/sendMessage 文案族**(`f88c367`):按行状态机映射官方 19 条 zh/en 文案(任务输出 · 已获取 / 停止任务 · 正在停止任务 / 发送消息 · 已发送 等)。
- **终端分组聚合**(`53d8967`):连续 2+ 条执行族工具行折叠为「终端 · N 个命令 · 失败/停止计数 · 首条命令预览」,点击展开;`assistantTurnParts` 新增 rowGroup 部件;3 个行为测试,245 全绿。
- **业务错误码翻译**:发送/命令失败的错误文本含业务码(1006/1005/3006/3001/3007/3008-3010/3002/2007/429)时,以官方文案替代原始传输错误(web `zcode.error.providerBusiness.*` 对齐;web 按 code+message 关键词分类成 升级/稍后重试 动作桶,横幅动作按钮待真实会话验证后跟进)。**i18n 记账(2026-09-16)**:zh 文案为官方原文,en 为**兜底翻译、非官方**,待用户从官方 web 实测取得 en 文案后**仅替换表值** `chat.bizErr.*`(零代码改动);测试 `test/ui/chat/business_error_copy_test.dart` 已锁 zh 原文与 en 无中文回落。
- **裁剪加载(snapshotRefs)→ ⚠️ 跳过(如实记录)**:schema 已挖到(`toolCall.snapshotRefs: [{field: input|output|raw, refId, hash, fullBytes, previewBytes}]`,notice 文案「该工具有 N 个字段被裁剪…」),但当前 web 构建中 `getTaskSnapshotToolCallsSlice` 只有离线 stub(返回 null),notice 组件在无 loader 时整块不渲染 —— **web 自身无可见行为可对齐**,实现它反而偏离 web。待 web 实装后跟进(schema 随本记录留存)。

## subagent 进度与详情批次实现记录(2026-09-13,任务 09-13-subagent-progress)

- **数据契约**:全部来自 live probe(`.trellis/tasks/09-13-subagent-progress/research/subagents-probe.md`):running 条目/subagent 行/backgroundWorks subagent 条目通过 `childSessionId`/`agentId`(=workId=entityId)/`toolCallId`(=parentToolCallId) 关联;子会话可直接 subscribeConversationV4(与父会话同构快照)。
- **C24**:协议层仅新增 `ConversationState.subagentsInfo` 类型化 getter(codec/delta 零改动);`_BackgroundWorksBar` 双形态(subagent 分行/bash 单行计数);详情页 `subagent_detail_page.dart` 只读订阅子会话(简化时间线+rowsRange 翻页+运行中停止=对父会话 cancelBackgroundWork);入口×3(works 行/_SubagentTile/GoalPanel running tile,后两者经可选 `onOpenAgent` 回调,goal_panel 不引入 gateway 依赖)。
- ⚠️ 已知差异:works 行不显示已运行时长(GoalPanel running tile 内已有 `_AgentElapsed`,works 行 MVP 未复制);详情页 running 标记为入口时快照,不随父会话 works 列表实时翻转;子会话内若出现 userInput 行按只读纯文本渲染(probe 窗口未捕获,防御处理)。
- ⚠️ 待核:mailbox 行(「来自 {sessionId} 的新消息」)两次探测样本均未出现,row kind 与结构未知(PRD Open Question);子会话详情页按默认轻量分隔渲染,待真实样本复测后跟进。
- 测试:conversation_test +2(subagentsInfo);chat_page_test +3(goal=null 可见/summaryText 流式更新/点击进详情);subagent_detail_page_test 新建 +3(只读时间线/loadOlder 调 rowsRange/停止确认)。

## subagent composer 入口批次实现记录(2026-09-17,任务 09-17-subagent-composer-entry)

- **C24 更新**:works 灰条收敛为 bash-only 单行计数(StatelessWidget,不再持 SubagentFeed 池引用);子智能体底部管理迁移到 composer pill(模式 chip 右侧,`subagentsRunningView`(`subagents.running[]` 终态滞回视图)非空渲染,全终态过 `turnFooterConfirmWindow` 销毁)+ 管理 sheet `_SubagentSheet`(运行区池化实时 tail+详情/停止带确认;已结束区=窗口终态行+rowsRange 翻更早,游标=`oldestRowId` 与已收集最小 rowId 较小者,翻页只进 sheet 本地列表不动 chat rows;dispose 对称释放池引用)。
- **rowsRange 游标修复**:`ConversationState.oldestRowId`(持有行最小 rowId)取代快照/响应 `firstRowId`(可为占位值 1,live-probe 实证);`prependOlderRows` 回写以实际新增行最小值为准,全重复页不动游标。chat_page/_SubagentSheet/subagent_detail_page 三处 `_loadOlder` 统一换用;「打开会话自动补一页」随之真实生效。
- ⚠️ 有意差异:pill 仅计子代理(官方混合 bash+子代理计数),bash 留 works 灰条避免双显;已结束区+翻更早为 native-only(web 无对应)。
- 测试:rows_range_parse_test +2(占位游标两页严格更旧/全重复页不动游标);chat_page_test works-bar 用例改造为 pill+sheet 族(销毁窗/滞回不复活/sheet 实时 tail/停止确认/翻页到头/关闭释放)。

## 套餐剩余批次实现记录(2026-09-14,任务 09-13-quota-remaining,代码完成,待桌面 entitlement 恢复后复测)

- **数据契约**:全部来自 live probe(`.trellis/tasks/09-13-quota-remaining/research/entitlement-probe.md`):会话快照顶层 20 key 无任何 quota/planUsage 推送 → C9 警告只能轮询 `usage-stats.getEntitlementSnapshot`;本机桌面返回 `not_configured`(provider/remaining/subscription/quota 全 null),即 entitlement 子系统状态与会话鉴权是两回事。
- **新增 state 层**:`lib/state/entitlement_poller.dart` — EntitlementPoller(ValueNotifier<EntitlementView>,phase: loading/ok/notConfigured/noPlan/loginRequired/error):5 分钟 staleness 缓存、force 绕过、并发去重、失败保旧值不清空(错误永不走缓存);`exhausted` 投影(仅 `quota.limits` 中 token 类 `TOKENS_LIMIT`/`CREDIT_LIMIT` 触顶;顶层 `remaining` 是月度 MCP `TIME_LIMIT` 的镜像、不参与——09-15 语义修正)为警告条唯一判据。DeviceSession 惰性持有(会话生命周期单例,dispose 关闭);ChatGateway 增转发方法 `entitlementSnapshot({bool force})`。
- **U3/U4**:用量页按 phase 五分支渲染(ok 态维持现有卡片不动;notConfigured/noPlan/loginRequired/error → 文案+重试,复用 tasks.retry);打开走缓存,刷新按钮/下拉 force。
- **U5/C10**:聊天页输入区 control row 曾常驻 `_QuotaPill`(剩余 N · HH:mm 重置),09-15 语义修正任务移除——它读的是 `remaining`(月度 MCP `TIME_LIMIT` 镜像),在 token 仅 51% 时就显示警告色「0」,误导性强;官方 composer 也无常驻 quota pill。用量入口由警告条「查看用量」(ChatPage.onOpenUsage 回调注入)与更多菜单「用量统计」承担。
- **C9**:警告条 = poller ok 且 exhausted(danger 色卡),动作 切换模型(复用 _showModelSheet)+ 查看用量;页面打开时拉一次,无后台常驻定时器(R4 本地通知联动移出范围,待有真实推送数据源再议)。渲染字段仅限已确认结构(remaining count/percentage/nextResetTime、quota.limits percentage),5 小时池/每周等未确认字段一律未渲染。
- 测试:entitlement_poller_test 新建 +8(staleness/force/失败保旧值/并发去重/五 phase 映射/exhausted 判据,not_configured 录制响应作 fixture);device_usage_page_test 新建 +7(五态+重试+loading);chat_page_test +4(pill ok/隐藏、警告条出现/动作、下一次 ok 解除)。全量 303 绿,analyze 0 警告(10 条既有 Radio info 为基线)。
- ⚠️ 待复测:用户在桌面 ZCode 打开一次用量页后复跑 audit 探针,确认 entitlement 恢复与真实 ok 返回结构,再补富字段渲染与真机截图验收(judge)。

## 重置机会批次实现记录(2026-09-14,任务 09-14-quota-reset-opportunity,代码完成,真机验收推迟)

- **数据契约**:全部来自官方 web 远控 bundle 逆向(`.trellis/tasks/09-14-quota-reset-opportunity/research/quota-reset-bundle-analysis.md`):usage-stats 通道 `getCodingPlanResetStatus`/`useCodingPlanReset`,快照渲染白名单仅 `availableFiveHourResets`/`availableWeekResets` 的 `expireAt`;官方乐观状态机 available→processing→completed,UUID 幂等键,成功后 force 重拉 status + force 刷新 entitlement。
- **新增 state 层**:`lib/state/quota_reset.dart` — `parseQuotaResetPools`(防御性纯函数,缺字段/类型错静默降级 count=0,过期条目按 bundle WF 语义排除)+ `QuotaResetController`(10s staleness 缓存、force 绕过、失败保旧值且错误不进缓存、乐观 processing、幂等键手写生成、成功链 force 确认 + entitlement force 刷新、失败回滚置 error);scope(`preferredProviderId`)由 UI 从 entitlement ok 快照 provider.id 防御性读出后 `updateScope` 注入,缺失=功能禁用态(不发请求、显示禁用文案、不弹错)。`ChatGateway` 增 `quotaResetStatus`/`useQuotaReset`/`quotaResetController`;DeviceSession 惰性持有控制器 + dispose 关闭,RPC 形态 `('usage-stats','getCodingPlanResetStatus',[scope])` / `('usage-stats','useCodingPlanReset',[{...scope,idempotencyKey,resetType}])`。
- **U6**:用量页 ok 态卡片列表末尾「重置机会」卡(两池行 count/最早过期/重置按钮、processing 转圈、暂无文案、禁用态文案、确认框、成功/失败 SnackBar、成功后页面 force 刷新);C9 增量:触顶警告条在任一池 count>0 时追加「使用重置券」(优先 5 小时池),确认→use→entitlement 重拉使警告条即时翻新。i18n `usage.reset.*` + `chat.quota.useReset` 双语。
- 测试:quota_reset_test 新建 +8(解析畸形输入/过期过滤/缓存与 force/成功链/失败回滚/scope 禁用);device_usage_page_test +4(两池渲染/无 provider id 禁用态/取消不发 RPC/确认成功链+降级不崩);chat_page_test +3(无机会不出现/取消不消耗/确认后警告条翻新)。全量绿。
- ⚠️ **TODO 真机复测**(桌面 provider 域修复后):复跑 `test/protocol/live_reset_opportunity_probe_test.dart`(env `ZLINKER_PROBE_URL` 驱动,未设置自动跳过)确认 ①status 快照真实字段与白名单一致 ②`useCodingPlanReset` 在真实通道的成功/失败形状 ③entitlement provider 是否携带 `id` 字段(scope 注入依据)。复测通过后再做真机手动验收(写操作消耗真实重置券)。
- **09-16 可见性过滤修正**(任务 09-16-reset-card-visibility):官方 bundle `_I` 聚合 + `hI` 入口的三条件谓词落为纯函数 `poolVisible`(quota_reset.dart)——①行存在:`MF(limits,'TOKENS_LIMIT',3,5)` / `MF(limits,'TOKENS_LIMIT',6)`,类型走官方别名集 `qYe`(`TOKENS_LIMIT` 查询同时命中 `CREDIT_LIMIT` 行);②`count>0`(官方 `opportunityVisible`);③`!FF(limit)`,而 `FF(limit) = PF(limit)==100`、`PF` 为剩余百分比 `clamp(100-percentage)`——即**窗口 0% 已用(未动)时隐藏**(percentage 缺失/非数/非有限按官方 `PF→null→FF=false` 视为可见);`processing` 保留官方乐观例外(在飞行中的池不消失)。用量页「重置机会」卡逐行过滤,两池都不可见时回落既有「暂无可用机会」文案(`usage.reset.none`),`pools==null` 禁用态不变;聊天页用量 sheet「重置券 · 可用 N 张」行按同一谓词只统计可重置的池,两池都不可见即隐藏入口(`使用重置券` 按钮同容器一并隐藏)→ 修掉「V1 套餐无周窗口行、账号周卡仍被展示/可重置」的语义分裂。零新文案。测试:quota_reset_test +8(谓词全覆盖:V1 fixture/行存在性/count=0/0% 与 100% 两端/percentage 缺失与畸形/processing 例外/未知池型与垃圾行)、device_usage_page_test +2(V1 隐周池、两池不可见回落)、chat_page_test +4(只计可重置池、不可重置即隐藏入口、弹窗过滤、弹窗空态防御);全量 396 绿,analyze 10 条既有 info 基线。
- **09-16 弹窗同源过滤**(同一任务的收口):`showQuotaResetDialog` 新增必填 `Set<String> resettable`(`quota_reset_dialog.dart`),弹窗按它过滤行与「重置」动作 —— 不可见的池既不渲染行也不给按钮;`resettable` 由调用方 `_UsageSheet._resettablePools(limits, pools)` 用同一个 `poolVisible` 算出并通过 `_UsageSheet.onUseReset`(签名由 `VoidCallback` 改为 `void Function(Set<String>)`)带给 `ChatPage._showResetDialog` —— 与「重置券 · 可用 N 张」行同一次求值,不存在两处判据漂移。两池都不可见时弹窗回落既有「暂无可用机会」文案(防御分支,入口已被 credits 拦下,UI 到不了)。测试:chat_page_test +2(V1 fixture 无周行/无周重置按钮;直接调 `showQuotaResetDialog(resettable: {})` 的防御空态)。

## 官方样式对齐批次实现记录(2026-09-15,composer/消息流/队列,用户逐项预览验收)

- **composer 圆角**:面板圆角 12=ZRadius.tile、发送/停止按钮 32×32 视觉 mini 6 方形(48 触摸区不变)——官方截图 PIL 像素实测(面板 12px、按钮 ~30px 角 6±1)。
- **运行中保留发送**:原 `running ? stop : send` 互斥渲染吞掉排队入口;改发送常驻 + running 时停止按钮追加右侧(官方像素:send ↑ 左、stop ■ 最右),_send() 本就支持运行中 held-queue。
- **代码默认收起**:markdown 代码块头部=语言+N 行+复制+折叠箭标(词条 chat.code.lines 双语);`_ToolCallTile` 的 diff/图片原渲染在 ExpansionTile children 之外(收起后仍全展开刷屏)——移入折叠区,收起只剩「已写入 file +N/-M」摘要行,运行中进度条常显;编辑类展开只显 diff(input/output 参数 JSON 不再透传;无 diff 工具如终端不受影响,error 始终保留)。
- **队列对齐官方**:容器去 sky 蓝高亮归 ZInk.tile 中性(token 语义本含 queue);队列非空时 placeholder 切官方文案「继续输入以排队后续修改」(chat.input.hint.queued);上移/下移箭头移除,每条独立卡片(card 色/field 8/hairline 边)+ drag_indicator 把手拖拽(ReorderableDragStartListener;本机 Flutter ≥3.41 的 onReorder 已废弃且测试拖拽不触发——须 onReorderItem,widget 测试拖拽用 startGesture+小步 moveBy+pump)。
- 测试:chat_page_test 增 tool-call 收起断言/拖拽 reorder 参数形状/running send+stop 并存可发送/placeholder 队列态;markdown_view_test 增折叠默认+展开收起切换;全量 346 绿。
