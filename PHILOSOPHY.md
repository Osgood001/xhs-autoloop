# Philosophy: Safeguard · Cultivate · Evaluate

*How to trust an AI Agent to work independently while you sleep.*

---

## The Problem

You want an AI Agent to do real work — not just answer questions, but take actions, produce outputs, iterate, improve. And you want it to keep running when you're not watching.

But three things will go wrong:

1. **It will crash.** APIs timeout, networks drop, services restart. Without you there to hit "retry", it just stops.
2. **It will do it wrong.** The first time, and probably the second time too. Its output won't meet your standards.
3. **It will lie to you.** Not maliciously — but it will confidently report "task completed" when the result is mediocre. It has no incentive to be self-critical.

This framework addresses all three with a three-layer closed loop.

---

## Layer 1: Safeguard (保障)

> *Don't expect any single run to succeed. Ensure the system can recover from any failure automatically.*

The Agent will encounter every kind of failure: API outages, network timeouts, MCP service restarts, prompts getting truncated, out-of-memory errors. You can't babysit it 24/7.

**The solution is a heartbeat mechanism that is completely independent of the Agent itself:**

```
cron (*/10 * * * *) → watchdog.sh
  ├── Is the mission still active?
  ├── Has enough time passed since last run?
  ├── Is the previous run still going? (tmux check)
  └── No? → Launch new round in isolated tmux session
       ├── Success → reset failure counter, wait for next interval
       └── Failure → increment counter, retry in 30 minutes
```

Key design principles:

- **The watchdog is a simple shell script, not an AI.** It doesn't think, it doesn't hallucinate, it doesn't get confused. It just checks timestamps and launches processes.
- **Each round is isolated.** tmux sessions are independent. One round crashing doesn't corrupt the next.
- **Exponential backoff by design.** Failed rounds retry faster (30min) than successful intervals (4h), but never spam.
- **Self-expiring missions.** Every mission has an end date. It won't run forever by accident.

**Safeguard answers the question: "Will this still be running when I wake up?"**

---

## Layer 2: Cultivate (培养)

> *Don't expect the Agent to get it right the first time. Teach it, test it, accumulate its experience into durable artifacts.*

AI Agents are not plug-and-play. The first run will produce garbage. This is normal and expected.

**The cultivation process:**

```
1. Run manually, watch it fail
2. Fix the constraints it violated
3. Let it run independently, verify output
4. Still broken? → Go to step 2
5. Good enough? → Crystallize the experience
```

This is exactly how you train a junior employee. You don't expect them to be productive on day one, but you also don't plan to hold their hand forever. **The goal is to get the Agent's average output to match your own casual-effort level.**

Experience crystallizes into three layers, each with a distinct role:

### Prompt — The Rules

What the Agent must follow every single round. Hard constraints.

```
"Never use Markdown formatting"
"Title must be ≤ 15 Chinese characters"
"Must curl real sources, never fabricate"
"Always verify publication with search_feeds"
```

These go in `prompt-template.md` and get injected every round.

### Skill — The Capabilities

When you notice the Agent repeatedly struggling with a complex multi-step process, package it as a [Claude Code Skill](https://docs.anthropic.com/en/docs/claude-code/skills). Next time, it just invokes the skill instead of figuring it out from scratch.

```
Example: "Fetch HN top stories → Filter AI-related →
          Rewrite for XHS audience → Format as plain text"
→ Package as a skill, install to ~/.claude/skills/
```

Skills are the Agent's **learned abilities** — things it can now do reliably because you taught it once and crystallized the process.

### Scripts — The Infrastructure

Scheduling, heartbeat, data collection, status checking — these should **never** depend on the Agent. They use deterministic shell scripts that always behave the same way.

```
Agent's job:  Think, create, reflect
Script's job: Schedule, keep alive, collect data
```

This separation is critical. If you let the Agent manage its own scheduling, it will eventually hallucinate a cron entry or forget to set up the next round. Scripts don't hallucinate.

```
Cultivation Artifacts:
  Prompt   → Per-round rules and strategy    (config/prompt-template.md)
  Skill    → Reusable capability modules     (~/.claude/skills/)
  Scripts  → Deterministic scheduling        (scripts/)
```

**Cultivate answers the question: "How do I make it good enough to trust?"**

---

## Layer 3: Evaluate (评价)

> *Never trust the Agent's self-assessment. Use objective, external metrics that the Agent cannot fabricate.*

Here's a dirty secret about AI Agents: **they will always tell you they did a good job.**

Ask an Agent to evaluate its own blog post, and it will say "well-structured, informative, engaging." Ask it to rate its own code, and it will say "clean, well-documented, handles edge cases." This is useless.

**The solution is an evaluation metric that is:**
1. **Objective** — a number, not a subjective assessment
2. **External** — comes from the real world, not from the Agent
3. **Unforgeable** — the Agent cannot manipulate it

In this project, the metric is **likes + collects from real Xiaohongshu users**.

```
score = liked_count + collected_count
```

This number comes from real humans who saw the content and decided whether it was worth engaging with. The Agent:
- Cannot fake it
- Cannot argue with it
- Must confront it every round

When the Agent sees "this post: 0 likes, 0 collects" next to "that post: 18 likes, 21 collects", its reflection becomes real. It can analyze *why* — "the title lacked emotional hook", "the content was too generic", "this topic doesn't resonate with the audience" — and these analyses actually mean something because they're grounded in objective data.

**The like-collect ratio reveals specific problems:**

| Pattern | Diagnosis | Action |
|---------|-----------|--------|
| collects >> likes | Valuable but lacks emotional hook | Improve titles, add relatable openings |
| likes >> collects | Emotionally resonant but not useful enough | Add more actionable content |
| Both low | Topic selection problem | Switch categories |
| Both high | Winning formula | Do more of this |

Without this evaluation layer, the Agent operates in **self-congratulation mode** — it writes, it publishes, it says "done!", and it never improves. With it, the Agent operates in **accountability mode** — it writes, it publishes, it checks the score, it adjusts.

**Evaluate answers the question: "How do I know it's actually doing a good job?"**

---

## The Closed Loop

These three layers form a closed loop that enables genuine autonomous operation:

```
┌─── Safeguard ──────────────────────────────────┐
│ System stays alive no matter what               │
│                                                 │
│  ┌─── Cultivate ────────────────────────────┐   │
│  │ Each round, Agent is a little better     │   │
│  │                                          │   │
│  │  ┌─── Evaluate ──────────────────────┐   │   │
│  │  │ Objective metrics drive           │   │   │
│  │  │ real improvement                  │   │   │
│  │  │                                   │   │   │
│  │  │  ┌───────────────────────────┐    │   │   │
│  │  │  │     Agent works here     │    │   │   │
│  │  │  └───────────────────────────┘    │   │   │
│  │  │                                   │   │   │
│  │  └───────────────────────────────────┘   │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

Remove any one layer and the system breaks:
- **No Safeguard** → It crashes at 3am and you don't find out until morning
- **No Cultivate** → It keeps making the same mistakes forever
- **No Evaluate** → It thinks it's great while producing garbage

---

## Beyond Xiaohongshu

This framework is not specific to content creation. It applies to **any scenario where you want an Agent to operate autonomously**:

| Scenario | Safeguard | Cultivate | Evaluate |
|----------|-----------|-----------|----------|
| **Content creation** | Watchdog + cron + tmux | Prompt + skill + scripts | Likes + collects |
| **Code review** | PR webhook + retry queue | Review rubric as skill | Bug escape rate |
| **Scientific experiments** | Job monitor + auto-resubmit | Experiment config templates | Objective reward metric |
| **Data monitoring** | Health check cron | Alert rule refinement | Anomaly detection accuracy |
| **Customer support** | Queue processor + dead letter | Response template library | CSAT score |

The key insight is always the same: **the Agent does the thinking, but the infrastructure does the guaranteeing.** Separate these concerns, and you can sleep peacefully.

---

*This philosophy was developed through real-world operation of xhs-autoloop, running 24/7 on a cloud server, autonomously publishing content to Xiaohongshu and iterating based on real engagement data.*
