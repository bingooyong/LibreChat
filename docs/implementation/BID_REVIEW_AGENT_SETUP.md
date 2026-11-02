# 招标文件智能分析助手 —— Agent 初始化说明

本文说明如何在 LibreChat Agent Builder 中创建「招标文件智能分析助手」。前置条件：MiniMax 端点已接入且 `MINIMAX_API_KEY` 已配置（见 `LIBRECHAT_CURRENT_STATE_AUDIT.md`）。

## 1. 前置条件核对

| 项 | 要求 | 如何确认 |
| -- | -- | -- |
| 端点已注册 | `/api/models` 含 `MiniMax CN` | `curl -H "Authorization: Bearer $TOKEN" localhost:3080/api/models` |
| Skill 已加载 | 启动日志有 `Loaded N deployment skill(s)` | 查后端日志 |
| 模型可调用 | 发送一条消息能收到回复 | 在 Web 界面实测 |

Skill 文件位于 `skill/bid-document-review/`，后端启动时自动加载，**不需要**重启即可生效；修改 `SKILL.md` 后需重启后端。

## 2. 创建 Agent

### 2.1 入口

Web 界面左侧栏 → Agents（智能体）→ Create（创建）。

### 2.2 基础信息

| 字段 | 填写内容 |
| -- | -- |
| Name（名称） | `招标文件智能分析助手` |
| Description（描述） | `分析上传的招标文件，提取资格条件与否决项，生成技术响应矩阵与审查报告。` |

### 2.3 模型

| 字段 | 填写内容 |
| -- | -- |
| Model（模型） | `MiniMax-M3.1-Flash`（备用：`MiniMax-M3`） |
| Instructions（指令） | 见下方「建议的 Agent 指令」 |

### 2.4 Skills

在 Skills 区块启用 `bid-document-review`。

该 Skill 为**部署级**（来自 `skill/` 目录），对所有用户只读可见。若列表中看不到，说明后端未加载，检查启动日志中的 `deploymentSkills` 行。

### 2.5 工具

只勾选**当前已验证可用**的工具：

| 工具 | 是否建议开启 | 说明 |
| -- | -- | -- |
| 文件检索 / 知识库检索 | 开启 | 用于匹配企业资质与业绩材料 |
| 代码执行 | 开启 | 用于评分项分值求和校验、表格生成 |
| Web 搜索 | **默认关闭** | 招标文件与企业材料属敏感信息，不应外发到外部服务 |

**未验证的工具先不开。** 每启用一个外部工具，都意味着招标文件内容可能流向第三方服务，与红线第 9 条冲突。

### 2.6 建议的 Agent 指令

```
你是招标文件分析助手。

工作规范由 bid-document-review Skill 定义，必须严格遵守：
- 所有结论必须有原文依据（条款原文 + 页码/章节）
- 缺少证据的内容一律标为「缺少证据」或「待人工确认」，不得判定为「完全符合」
- 不得编造企业资质、项目业绩、产品参数或技术承诺
- 不得自动作出最终投标决策

输出遵循 Skill 中 references/output-schema.md 定义的表格格式。

如果招标文件未上传或无法解析，直接说明缺少什么，不要用通用知识补齐。
```

### 2.7 Conversation Starters（会话开场白）

在 Agent 设置中填入四条：

```
分析我上传的招标文件。
提取全部资格条件与否决项。
生成技术评分响应矩阵。
检查企业资质和业绩材料缺口。
```

## 3. 验收测试

创建完成后，用一份真实招标文件逐项验证：

| 验收项 | 预期 | 判定方法 |
| -- | -- | -- |
| 端点加载 | 模型选择器出现 `MiniMax CN` | Web 界面 |
| 模型可选 | 列出 `MiniMax-M3.1-Flash` 与 `MiniMax-M3` | Web 界面 |
| 普通聊天 | 返回中文回复 | 发送「你好」 |
| 流式输出 | 逐字返回而非整段 | 观察 UI |
| 多轮上下文 | 第二轮能引用第一轮内容 | 追问「刚才的项目名称是？」 |
| Tool Calling | 能调用代码执行并返回结果 | 让它做评分项求和 |
| Skill 生效 | 输出符合 output-schema.md 的表格 | 上传招标文件 |
| 证据定位 | 每条结论能对应到页码 | 抽查 3 条 |
| 缺证据处理 | 无材料时标「缺少证据」而非「完全符合」 | 只传招标文件不传企业材料 |

任一项失败时，先判断归因：

| 现象 | 归因 |
| -- | -- |
| 模型选择器无 MiniMax | `librechat.yaml` 未加载或校验失败 → 查后端启动日志 |
| 报 `Missing API Key` | `.env` 中 `MINIMAX_API_KEY` 未填 → 管理员填写 |
| 401 / authentication_error | Key 无效或账号区域与 `api.minimaxi.com` 不匹配 |
| 404 / model_not_found | 模型名与账号不匹配 → 查平台可用模型列表 |
| 流式中断 | MiniMax 兼容层对 SSE 的支持 → 检查上游文档 |
| 工具调用失败 | Agent 工具配置问题，与模型接入无关 |
| Skill 未生效 | 后端未加载 deployment skills → 查日志 |

## 4. 不通过 Beta API 自动创建的原因

本次不通过 API 预创建 Agent，理由：

- Agent 的 Skills、工具集、指令等字段会随 LibreChat 版本演进，脚本化创建容易在升级后失效
- 部署级 Skill 需在 Agent 中显式启用并保存，这个动作在 Web 界面完成更直观
- 人工走一遍创建流程，能顺带验证 Agent Builder 与 Skills 的联动是否正常

后续若确有批量创建的自动化需求，再评估走 API。

## 5. 后续维护

| 变更 | 需要重启后端 |
| -- | -- |
| 修改 `skill/bid-document-review/SKILL.md` | 是 |
| 修改 `skill/bid-document-review/references/*.md` | 是 |
| 修改 `librechat.yaml` | 是 |
| 修改 Agent 的指令或工具集 | 否（Web 界面保存即生效） |
| 新增用户级 Skill | 否 |
