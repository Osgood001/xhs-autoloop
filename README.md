# xhs-autoloop

让 Claude Code 全自动运营你的小红书账号：选题、写稿、发布、追踪数据、反思迭代，7×24 无人值守。

## 核心哲学：保障 · 培养 · 评价

这不是一个"一键发帖脚本"。这是一个**让 AI Agent 在你睡觉时也能聪明做事**的系统。

它背后的设计理念来自一个核心问题：**你怎么信任一个 Agent 独立工作？**

答案是三层闭环：

### 1. 保障（Safeguard）— 确保系统永远在跑

Agent 会遇到各种意外：API 临时断了、网络抖动、MCP 服务重启、prompt 太长被截断。你不可能 24 小时盯着它。

所以需要一个**独立于 Agent 的保活机制**：
- Watchdog 每 10 分钟检查心跳
- 失败自动重试（30 分钟后）
- 成功则按正常间隔继续（4 小时）
- 过期自动停止，不会无限跑
- tmux 隔离，一轮崩溃不影响下一轮

保障的核心是：**不要指望任何单次运行一定成功，而是确保系统能从失败中自动恢复。**

### 2. 培养（Cultivate）— 不要指望它一次就会

AI Agent 不是开箱即用的。**第一次一定要手把手带它走完全流程**：
1. 手动运行一轮，看它哪里做错了
2. 修正 prompt，补充它遗漏的约束
3. 让它独立跑一轮，验证是否"出师"
4. 如果又出问题，继续调整，直到产出达到你的基准
5. 把经验沉淀到 prompt 和配置里

这就像带新人：你不会第一天就让实习生独立上线，但你也不会每天帮他写代码。**培养的目标是让 Agent 的平均产出达到你一般状态下的水准。**

本项目的 prompt 模板就是"培养"的成果——它包含了：
- 从实际运行中踩过的坑（纯文本、不用 Markdown、必须 curl 真实信源）
- 被验证有效的内容策略（标题情绪化 + 正文干货化）
- 从数据中学到的反思框架（赞藏比分析）

### 3. 评价（Evaluate）— 用客观指标代替自我感觉

**任何 Agent 都可能"自信地汇报完成了任务，但实际上没有。"**

如果你让 Agent 自己评价自己的内容质量，它永远会说"写得不错"。这毫无意义。

解决方法是给它一个**客观的、独立于它的评价指标**：
- 点赞数 + 收藏数 = score
- 这个数字来自真实用户，Agent 无法伪造
- 每轮循环必须查上一轮的实际数据
- 用数据驱动反思，而不是自我感觉

当 Agent 看到"这篇 0 赞 0 藏"vs"那篇 18 赞 21 藏"，它的反思才是真实的。**评价体系把 Agent 从"自嗨模式"拉到"对结果负责模式"。**

```
保障：系统在你睡觉时也不会停
  └─> 培养：每一轮 Agent 都比上一轮更熟练
        └─> 评价：客观数据，不靠 Agent 自我感觉
              └─> 反馈回保障：数据异常自动触发修正
```

> **这三层是通用的。** 不只是小红书——任何你想让 Agent 自主运行的场景（内容创作、代码审查、数据监控、科研实验），都需要这三层。本项目是一个可运行的参考实现。

## 架构

```
┌─────────────────────────────────────────────┐
│  cron (*/10 * * * *)                        │
│  └── watchdog.sh                            │
│       ├── 读 mission.json（状态/迭代/间隔） │
│       ├── 检查：该跑了吗？上一轮结束了吗？  │
│       └── tmux → claude --print < prompt    │
│            │                                │
│            ├── 查数据 (search_feeds)         │
│            ├── 存档 (metrics.jsonl)          │
│            ├── 反思 (赞藏比分析)             │
│            ├── 抓信源 (curl HN/自定义)       │
│            ├── 发帖 (publish_content)        │
│            └── 验证 (search_feeds 确认)      │
└─────────────────────────────────────────────┘
```

## 前置条件

- 一台 Linux 服务器（1C1G 即可，能跑 Claude Code 就行）
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 已安装
- [xiaohongshu-mcp](https://github.com/anthropics/xiaohongshu-mcp) 服务已运行并完成扫码登录
- `jq`、`tmux` 已安装
- Claude Code 的 API 配置（官方 API 或兼容 API）

## 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/Osgood001/xhs-autoloop.git
cd xhs-autoloop
```

### 2. 配置

```bash
cp config/config.example.json config/config.json
```

编辑 `config/config.json`，填入你的配置：

```jsonc
{
  // 你已有的帖子标题，Agent 会追踪它们的数据
  "tracked_posts": [
    "你的第一篇帖子标题",
    "你的第二篇帖子标题"
  ],

  // 选题方向（至少保留 2 个，可自定义）
  "content_categories": {
    "A": {
      "name": "官方薅羊毛",
      "description": "各平台官方免费额度、学生优惠等",
      "sources": ["https://hacker-news.firebaseio.com/v0/topstories.json"],
      "examples": ["Claude免费额度最大化", "GitHub学生包申请全流程"]
    }
    // ... 更多类别见 config.example.json
  },

  // 内容风格
  "style": {
    "tone": "口语化、有温度、像朋友分享",
    "title_max_chars": 15,
    "body_max_chars": 900,
    "use_emoji": true,
    "language": "zh-CN"
  },

  // 调度
  "schedule": {
    "interval_hours": 4,
    "retry_minutes": 30,
    "mission_days": 7,
    "max_timeout_seconds": 1800
  },

  // 硬规则（建议不要改）
  "rules": {
    "no_markdown": true,
    "no_real_names": true,
    "must_verify_after_publish": true,
    "must_curl_sources": true
  }
}
```

### 3. 配置 Claude Code

确保 Claude Code 可以 headless 运行：

```bash
# 方式一：官方 API
export ANTHROPIC_API_KEY="sk-ant-..."

# 方式二：兼容 API（如 GPUGeek 等）
export ANTHROPIC_BASE_URL="https://your-api-provider.com"
export ANTHROPIC_API_KEY="your-key"
```

确保 xiaohongshu-mcp 已配置到 Claude Code：

```bash
# 编辑 Claude Code MCP 配置
# ~/.claude/mcp.json 或通过 claude mcp add 命令
{
  "mcpServers": {
    "xiaohongshu": {
      "url": "http://localhost:18060/mcp"
    }
  }
}
```

### 4. 一键启动

```bash
./scripts/setup.sh
```

这会：
- 验证所有依赖
- 从 `config.json` 生成 `mission.json` 和定制 prompt
- 注册 cron 任务
- 立即触发第一轮

### 5. 查看状态

```bash
./scripts/status.sh
```

输出示例：
```
=== XHS AutoLoop Status ===
Mission: active | Round: 5 | Failures: 0
Next run: ~2h from now
Last run: 2026-03-30 14:05 (success)

=== Recent Metrics ===
关机后CC还在跑 是这样配的    likes=8  collects=8  score=16
CC每次踩坑都能自动记住       likes=9  collects=19 score=28
CC和Codex协作，效率真的翻了  likes=18 collects=21 score=39
```

## 文件结构

```
xhs-autoloop/
├── README.md
├── LICENSE
├── config/
│   ├── config.example.json    # 配置模板
│   └── prompt-template.md     # prompt 模板（高级用户可自定义）
├── scripts/
│   ├── setup.sh               # 一键安装
│   ├── watchdog.sh            # 核心看门狗
│   ├── status.sh              # 查看状态
│   ├── stop.sh                # 停止循环
│   └── renew.sh               # 续期（延长 mission）
└── data/                      # 运行时数据（自动生成）
    ├── mission.json
    └── metrics.jsonl
```

## 自定义指南

### 换信源

编辑 `config/config.json` 的 `content_categories`，每个类别可以指定：
- `sources`：Agent 用 curl 抓取的 URL 列表
- `examples`：给 Agent 的选题示例
- `description`：类别描述，引导 Agent 理解方向

```json
{
  "F": {
    "name": "独立开发",
    "description": "独立开发者的产品、收入、经验分享",
    "sources": ["https://www.indiehackers.com/feed.json"],
    "examples": ["月入1万的独立开发副业", "从0到1的产品发布清单"]
  }
}
```

### 换风格

修改 `config/config.json` 的 `style` 部分：

```json
{
  "style": {
    "tone": "专业严谨、数据驱动、像行业分析师",
    "title_max_chars": 20,
    "body_max_chars": 800,
    "use_emoji": false,
    "extra_instructions": "每篇必须包含至少一个数据佐证"
  }
}
```

### 换平台（高级）

prompt 模板在 `config/prompt-template.md`，你可以修改发布逻辑来适配其他平台的 MCP。核心循环（查数据→存档→反思→创作→验证）是通用的。

## 运维

### 查看完整日志
```bash
tail -100 ~/xhs-autoloop/data/mission.log
```

### 手动触发一轮
```bash
./scripts/watchdog.sh  # 如果距上次运行超过 interval 就会触发
```

### 停止
```bash
./scripts/stop.sh      # 设置 mission status=paused
```

### 续期
```bash
./scripts/renew.sh 7   # 续期 7 天
```

## FAQ

**Q: 为什么不直接写一个 Python 脚本自动发帖？**

因为那只解决了"发"的问题。这个系统解决的是**持续产出好内容**的问题。Claude 能理解语境、分析数据、调整策略——这不是模板能做到的。

**Q: API 费用大概多少？**

每轮大约消耗 10-30k tokens（取决于信源长度），4 小时一轮，一天 6 轮。用 Sonnet 模型大约 $0.5-1/天。

**Q: 会不会发出低质量内容？**

prompt 里有硬约束（字数限制、格式要求、必须真实信源），加上 Agent 自己会看数据反思。如果某类内容持续低分，它会自动放弃。你也可以随时看 metrics 介入调整。

**Q: 小红书封号风险？**

本项目通过 MCP 操作浏览器，行为模式和真人一致。但任何自动化都有风险，建议：
- 不要设太高频率（4h+ 间隔）
- 内容保持原创和有价值
- 不要用来做营销号

## License

MIT
