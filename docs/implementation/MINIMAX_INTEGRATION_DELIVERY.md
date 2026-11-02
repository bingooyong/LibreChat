# MiniMax 接入交付清单

日期：2026-11-02
分支：`feat/my-work`（fork: `bingooyong/LibreChat`）

## 1. 变更清单

| 文件 | 类型 | 说明 |
| -- | -- | -- |
| `librechat.yaml` | 新建（**gitignore，未入库**） | MiniMax 自定义端点配置 |
| `.env.example` | 修改 | 新增 `MINIMAX_API_KEY` 占位符 |
| `.env` | 修改（**gitignore，未入库**） | 新增空变量 `MINIMAX_API_KEY=`，待管理员填写 |
| `scripts/smoke-test-minimax-anthropic.sh` | 新建 | 独立验证上游 API |
| `skill/bid-document-review/SKILL.md` | 新建 | 招标文件分析 Skill |
| `skill/bid-document-review/references/review-checklist.md` | 新建 | 审查清单 |
| `skill/bid-document-review/references/output-schema.md` | 新建 | 输出格式定义 |
| `docs/implementation/LIBRECHAT_CURRENT_STATE_AUDIT.md` | 新建 | 工程现状审计 |
| `docs/implementation/BID_REVIEW_AGENT_SETUP.md` | 新建 | Agent 初始化说明 |
| `docs/implementation/MINIMAX_INTEGRATION_DELIVERY.md` | 新建 | 本文档 |

**未改动**：`packages/api` 核心实现、Anthropic SDK、MongoDB 数据、认证与权限逻辑、依赖版本。

`librechat.yaml` 被上游 `.gitignore` 覆盖（第 79 行），属 LibreChat 的既定约定：实例级配置不入库。该文件不含任何密钥（只引用 `${MINIMAX_API_KEY}`），若团队希望共享配置基线，可用 `git add -f librechat.yaml` 强制加入。

## 2. 配置文件内容

### `librechat.yaml`

```yaml
# Configuration version (required)
version: 1.3.18

endpoints:
  custom:
    - name: "MiniMax CN"
      provider: "anthropic"
      apiKey: "${MINIMAX_API_KEY}"
      # Anthropic SDK 会自动追加 /v1/messages，因此此处只填 API 根路径
      baseURL: "https://api.minimaxi.com/anthropic"
      headers:
        anthropic-version: "2023-06-01"
      models:
        default:
          - "MiniMax-M3.1-Flash"
          - "MiniMax-M3"
        fetch: false
      titleConvo: true
      titleModel: "MiniMax-M3.1-Flash"
      modelDisplayLabel: "MiniMax"
```

**`version` 是必填项** —— 缺失会导致后端启动即退出并报 `ZodError: expected string, path: ["version"]`。

### `.env` 追加项

```bash
# MiniMax (Anthropic-compatible endpoint)
MINIMAX_API_KEY=<你的 Key>
```

## 3. 启动方式

本项目当前采用 **Node.js 本地启动**（非 Docker Compose），因此**不需要**为 `librechat.yaml` 增加 Docker 卷挂载。

```bash
# 1. MongoDB（一次性）
docker run -d --name librechat-mongo -p 27017:27017 \
  -v librechat-mongo-data:/data/db mongo:8 --noauth

# 2. 依赖（注意：不要用 bun install，见审计报告 8.2）
MONGOMS_DISABLE_POSTINSTALL=1 npm install

# 3. 构建
npm run build

# 4. 启动
NODE_ENV=production node api/server/index.js
```

访问 http://localhost:3080

若日后改用 Docker Compose，需要在 `docker-compose.override.yml` 中增加：

```yaml
services:
  api:
    volumes:
      - type: bind
        source: ./librechat.yaml
        target: /app/librechat.yaml
        read_only: true
      - type: bind
        source: ./skill
        target: /app/skill
        read_only: true
```

## 4. 管理员需要完成的操作

**在项目根目录 `.env` 中填写：**

```
MINIMAX_API_KEY=<你的 MiniMax API Key>
```

填完重启后端即可生效。

注意：MiniMax 的按量付费 API Key 与 M Plan 订阅 Key 是不同凭证体系，需使用与账号和套餐匹配的 Key。

### 用 curl 调 API 时的注意事项

LibreChat 有一个反滥用机制：请求的 User-Agent 若无法解析为浏览器，会记为 `non_browser` 违规，累计到 `BAN_INTERVAL`（默认 20）次就封禁该账号 120 分钟。

用 curl 做 API 测试时**必须带浏览器 UA**，否则账号会被封：

```bash
UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
curl -A "$UA" -H "Authorization: Bearer $TOKEN" ...
```

另外，每调一次 API 都重新登录会放大违规计数——复用同一个 token 即可。

若已被封禁，解除方式（本地开发环境）：

```javascript
// mongosh LibreChat
db.logs.deleteMany({ key: { $regex: '^(ban|BANS)' } });   // 清除封禁记录（4 条）
```

```bash
redis-cli DEL "violations:non_browser:non_browser:<userId>"   # 清除违规计数
```

封禁期间该用户的 session 也会被清除，需要重新登录。

## 5. 验证结果

配置真实 API Key 后，全部验收项已实测通过。

| 验证项 | 结果 | 证据 |
| -- | -- | --- |
| `librechat.yaml` 校验 | **已验证** | 后端启动成功，无 ZodError |
| 端点注册 | **已验证** | `/api/models` 返回 `"MiniMax CN": ["MiniMax-M3.1-Flash", "MiniMax-M3"]` |
| 模型选择器显示 | **已验证** | Web 界面模型选择器出现「MiniMax CN」，展开列出两个模型 |
| baseURL 路径正确性 | **已验证** | 用假 Key 请求 `https://api.minimaxi.com/anthropic/v1/messages` 返回 **HTTP 401**（非 404），错误体为 Anthropic 标准格式 `{"type":"error","error":{"type":"authentication_error",...}}` |
| 协议兼容性 | **已验证** | 上游返回 Anthropic Messages API 格式的错误结构，与 `provider: anthropic` 匹配 |
| 上游 API 实际调用 | **已验证** | 冒烟脚本 HTTP 200，模型回「MiniMax连接成功」 |
| 普通聊天 | **已验证** | 回复「招标文件是招标人发布的、载明项目需求、投标资格、招标程序及评审标准等内容的正式文件。」 |
| 流式输出 | **已验证** | UI 逐段渲染；思考内容区块（`{"type":"think"}`）被正确解析并持久化 |
| 多轮上下文 | **已验证** | 第二轮追问准确复述第一轮的四个方面，未重复定义 |
| 会话标题生成 | **已验证** | `titleConvo` 自动生成标题「招标文件简介」，落库 `endpoint: MiniMax CN` |
| Tool Calling（协议层） | **已验证** | 直连上游：`stop_reason: tool_use`，发出 Anthropic 格式 `tool_use` 块（`get_weather` / `{"city":"北京"}`） |
| Tool Calling（端到端） | **已验证** | Agent 实际调用 MCP 工具 `http_ping`，收到 `E2E HTTP MCP pong`，模型据此生成结果表格 |
| MCP 连接 | **已验证** | 日志 `[MCP][local-test-mcp] Connection successfully established` |
| Skill 加载 | **已验证** | 启动日志 `Loaded 1 deployment skill(s)`；`/api/skills` 返回该 Skill（`source: deployment`, `fileCount: 2`） |
| Skill 正文注入 | **已验证** | Agent 准确引用仅存在于 SKILL.md 的内容：「核心原则」段、E 节五个合法符合状态、G-4/G-7 编号项、C 节「风险说明/需要人工确认」、边界小节「文档未载明」 |
| Agent Builder 创建 | **已验证** | Agent `agent_j4iARW8fOmX1SRPmubmMu`，模型 `MiniMax-M3.1-Flash`，挂载 MCP 工具与 Skill，4 条对话启动器 |
| Skill 约束实际生效 | **已验证** | 无招标文件时模型主动声明「当前对话中尚无可用招标文件材料，相关结论一律标记为『缺少证据 / 待人工确认』」 |
| MiniMax 对 Anthropic 特有参数（`thinking`）的兼容性 | **已验证** | 上游返回 thinking 块，LibreChat 正确渲染「思考内容」 |
| 招标文件真实解析 | **未验证** | 尚未用真实招标文件回归，输出矩阵的证据定位可靠性待验 |

### 已创建的 Agent

| 项 | 值 |
| -- | --- |
| Agent ID | `agent_j4iARW8fOmX1SRPmubmMu` |
| 名称 | 招标文件智能分析助手 |
| 模型 | `MiniMax CN` / `MiniMax-M3.1-Flash` |
| 工具 | `http_ping_mcp_local-test-mcp` |
| Skills | `bid-document-review`（`skills_enabled: true`） |

**`local-test-mcp` 是连通性测试用的 e2e 夹具**（`e2e/setup/fake-mcp-http-server.js`），仅用于验证工具回路，不代表生产工具集。生产环境应替换为真实的文件检索与代码执行工具：

```bash
# 启动夹具（Agent 依赖它）
E2E_MCP_HTTP_PORT=8765 node e2e/setup/fake-mcp-http-server.js

# 移除它（同时从 Agent 的 tools 里摘掉 http_ping_mcp_local-test-mcp）
curl -X DELETE http://localhost:3080/api/mcp/servers/local-test-mcp \
  -H "Authorization: Bearer $TOKEN"
```

## 6. 风险

| 风险 | 等级 | 说明 | 应对 |
| -- | -- | -- | --- |
| Key 缺失导致端点不可用 | 低 | 错误信息明确指向 Key，不会静默失败 | 管理员填写 `.env` |
| Key 区域与端点不匹配 | 中 | MiniMax 按量付费与 M Plan 可能分属不同区域 | 冒烟脚本会暴露 401；必要时换 `api.minimax.chat` 等区域端点 |
| 模型名不被账号授权 | 中 | 上游返回 `model_not_found` | 以平台实际可用模型列表为准 |
| Anthropic 特有参数不兼容 | 中 | `thinking` / `cache_control` 可能被拒 | 优先用 `customParams.paramDefinitions` 限制参数，不改核心代码 |
| `titleModel` 触发额外请求 | 低 | 标题生成失败应不影响主对话 | 若上游对并发敏感，可去掉 `titleConvo` |
| Skill 内容误判 | 中 | AI 可能把「缺少证据」判成「完全符合」 | 用真实招标文件回归；输出格式已强制证据列 |
| 招标文件外泄 | 低 | 仅开启内部知识库与代码执行工具 | 保持 Web 搜索关闭；不上传企业材料到外部服务 |

## 7. 下一阶段

见 `LIBRECHAT_CURRENT_STATE_AUDIT.md` 第 9 节与 `BID_REVIEW_AGENT_SETUP.md`。P0 已在本次完成（MiniMax 接入 + 多模型切换 + Agent Builder + Skills 加载 + 文件上传能力具备）；P1–P3 待 MiniMax 实际调用验证通过后，用一份真实招标文件回归后再排期。
