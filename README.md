<p align="center">
  <img src="assets/logo.svg" alt="xhs-autoloop" width="520"/>
</p>

<p align="center">
  <strong>Autonomous content engine for Xiaohongshu, powered by Claude Code.</strong><br/>
  <em>It selects topics, writes posts, publishes, tracks metrics, reflects, and iterates — 24/7, unattended.</em>
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> &nbsp;·&nbsp;
  <a href="PHILOSOPHY.md">Philosophy</a> &nbsp;·&nbsp;
  <a href="#customization">Customization</a> &nbsp;·&nbsp;
  <a href="#faq">FAQ</a>
</p>

---

## How It Works

You configure a server, scan a QR code to log in to Xiaohongshu once, run `setup.sh`, and go to sleep.

A cron-based watchdog launches Claude Code every few hours in a tmux session. Each round, Claude autonomously:

1. **Checks metrics** — queries likes and collects for all tracked posts via MCP
2. **Archives data** — appends scores to `metrics.jsonl`
3. **Reflects** — analyzes what's working (collect-heavy = useful but cold; like-heavy = engaging but shallow)
4. **Selects a topic** — picks from configured categories, avoids repeating recent types
5. **Fetches sources** — curls real data from HN, GitHub Trending, or your custom feeds
6. **Writes and publishes** — creates a post in the right style and format, publishes via MCP
7. **Verifies** — searches for the published post to confirm it's live

```
┌─ cron ─── watchdog.sh ────────────────────────────────────┐
│                                                            │
│  check metrics → reflect → pick topic → fetch → write →   │
│  publish → verify → log to metrics.jsonl                   │
│                                                            │
│  Failure? → auto-retry in 30min                            │
│  Success? → wait for next interval (default 4h)            │
└────────────────────────────────────────────────────────────┘
```

## Design Philosophy

This system is built on three principles: **Safeguard · Cultivate · Evaluate**.

- **Safeguard** — The watchdog keeps the system alive through API failures, network drops, and crashes. It doesn't depend on the Agent.
- **Cultivate** — The prompt, skills, and scripts encode accumulated experience. Each iteration is better than the last.
- **Evaluate** — Likes + collects from real users are the objective metric. The Agent cannot fake them or argue with them.

These three layers form a general framework for autonomous Agent operation — not just for content creation.

**[Read the full philosophy →](PHILOSOPHY.md)**

## Prerequisites

| Dependency | Notes |
|-----------|-------|
| Linux server | 1C1G minimum. Needs `jq`, `tmux`, `cron`. |
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Installed, able to run headless (`claude --print`). |
| [xiaohongshu-mcp](https://github.com/anthropics/xiaohongshu-mcp) | Running and authenticated (QR code login). |
| API access | Anthropic API or compatible provider. |

## Quick Start

**1. Clone**

```bash
git clone https://github.com/Osgood001/xhs-autoloop.git
cd xhs-autoloop
```

**2. Configure**

```bash
cp config/config.example.json config/config.json
```

Edit `config/config.json`:

<details>
<summary>Key fields</summary>

```jsonc
{
  "tracked_posts": ["Your post title 1", "Your post title 2"],

  "content_categories": {
    "A": {
      "name": "Official freebies",
      "description": "Free tiers, student packs, official credits",
      "sources": ["https://hacker-news.firebaseio.com/v0/topstories.json"],
      "examples": ["Maximize Claude free tier", "GitHub Student Pack guide"]
    }
    // Add more categories — at least 2 required
  },

  "style": {
    "tone": "Casual, warm, like a friend sharing tips",
    "title_max_chars": 15,
    "body_max_chars": 900,
    "use_emoji": true
  },

  "schedule": {
    "interval_hours": 4,       // Time between rounds
    "retry_minutes": 30,       // Retry delay on failure
    "mission_days": 7          // Auto-expire after N days
  },

  "claude": {
    "api_base_url": "",        // Leave empty for official Anthropic API
    "api_key": "sk-ant-..."
  },

  "mcp": {
    "xiaohongshu_url": "http://localhost:18060/mcp"
  }
}
```

</details>

**3. Set up Claude Code MCP**

```bash
# Ensure xiaohongshu-mcp is configured
cat ~/.claude/mcp.json
# Should contain: { "mcpServers": { "xiaohongshu": { "url": "http://localhost:18060/mcp" } } }
```

**4. Launch**

```bash
./scripts/setup.sh
```

This validates dependencies, generates `mission.json` from your config, registers the cron job, and triggers the first round.

**5. Monitor**

```bash
./scripts/status.sh
```

```
=== XHS AutoLoop Status ===
Mission:   active
Round:     12
Failures:  0
Next run:  ~1h47m
Expires:   2026-04-06 (5d left)

=== Recent Posts ===
🔥 CC和Codex协作，效率真的翻了      ❤️ 18   ⭐ 21   = 39
🔥 CC每次踩坑都能自动记住            ❤️ 9    ⭐ 19   = 28
🔥 关机后CC还在跑 是这样配的         ❤️ 8    ⭐ 8    = 16
```

## Project Structure

```
xhs-autoloop/
├── README.md
├── PHILOSOPHY.md                # Design philosophy deep-dive
├── LICENSE
├── assets/
│   └── logo.svg
├── config/
│   ├── config.example.json      # Configuration template
│   └── prompt-template.md       # Prompt template (advanced customization)
├── scripts/
│   ├── setup.sh                 # One-click setup
│   ├── watchdog.sh              # Core heartbeat daemon
│   ├── status.sh                # Status dashboard
│   ├── stop.sh                  # Pause the loop
│   └── renew.sh                 # Extend mission duration
└── data/                        # Runtime data (gitignored)
    ├── mission.json
    ├── metrics.jsonl
    └── mission.log
```

## Customization

### Content Sources

Each category in `content_categories` has `sources` (URLs for curl), `examples` (topic ideas), and `description` (guides the Agent's direction):

```json
{
  "G": {
    "name": "Indie Hacking",
    "description": "Solo dev products, revenue stories, launch playbooks",
    "sources": ["https://www.indiehackers.com/feed.json"],
    "examples": ["Side project hitting $10k MRR", "Zero to launch checklist"]
  }
}
```

### Writing Style

```json
{
  "style": {
    "tone": "Professional, data-driven, like an industry analyst",
    "title_max_chars": 20,
    "use_emoji": false,
    "extra_instructions": "Every post must include at least one data point"
  }
}
```

### Prompt Template

`config/prompt-template.md` uses `{{VARIABLE}}` placeholders, automatically filled from `config.json` by `setup.sh`. You can restructure the prompt, add steps, or change the reflection framework.

### Platform Adaptation

The core loop (check → archive → reflect → create → verify) is platform-agnostic. To adapt for a different platform, swap the MCP and adjust the publish/verify steps in the prompt template.

## Operations

```bash
./scripts/status.sh          # Dashboard
./scripts/stop.sh            # Pause
./scripts/renew.sh 7         # Extend by 7 days
./scripts/watchdog.sh        # Manual trigger (respects interval)
tmux attach -t xhs-loop      # Watch current round live
tail -f data/mission.log     # Full logs
```

## FAQ

<details>
<summary><strong>Why not just write a Python script to auto-post?</strong></summary>

A script solves "posting." This system solves "continuously producing good content." Claude understands context, analyzes data, and adjusts strategy — that's not something a template can do.

</details>

<details>
<summary><strong>How much does the API cost?</strong></summary>

~10-30k tokens per round (depends on source length). At 6 rounds/day with Sonnet, roughly $0.5-1/day.

</details>

<details>
<summary><strong>Will it produce low-quality content?</strong></summary>

The prompt enforces hard constraints (length limits, formatting rules, real sources required). The evaluation layer means the Agent sees real engagement data and drops underperforming content types automatically. You can also review `metrics.jsonl` anytime.

</details>

<details>
<summary><strong>Account risk?</strong></summary>

The MCP controls a real browser — behavior patterns match human usage. But all automation carries risk. Recommendations: keep intervals at 4h+, prioritize original valuable content, don't use it as a spam bot.

</details>

<details>
<summary><strong>Can Safeguard · Cultivate · Evaluate be used for other scenarios?</strong></summary>

Yes. See <a href="PHILOSOPHY.md#beyond-xiaohongshu">Philosophy → Beyond Xiaohongshu</a> for examples including code review, scientific experiments, and data monitoring.

</details>

## License

[MIT](LICENSE)
