# architect

A Claude Code skill that stops your most expensive model from typing.

The session model reads the codebase, makes the design decisions, writes a brief and reviews the diff. A cheaper worker agent writes the code from that brief and is thrown away when the slice is done. The skill is the contract between them: what goes in a brief, which slice goes to which worker, and what the review must check before a diff is accepted.

Measured over five weeks on one repo (49 sessions, 85 worker runs): the main model went from 7.9 source-file edits per 100 prompts to 0.4, and the Opus share of worker tokens went from all of them to about 4%. Total tokens per prompt ended up roughly where they started. The point is not fewer tokens, it is which model spends them. The full measurement is in [the blog post](https://www.flowhunt.io/blog/ai-coding-agent-architect-pattern-token-usage/).

## Install

```bash
git clone https://github.com/LivinTribunal/architect-skill.git
cd architect-skill
mkdir -p ~/.claude/skills/architect ~/.claude/agents ~/.claude/hooks
cp SKILL.md ~/.claude/skills/architect/
cp agents/*.md ~/.claude/agents/
cp hooks/architect-guard.sh ~/.claude/hooks/
```

For one project instead of your whole account, use `.claude/skills/architect/` and `.claude/agents/` inside the repo.

Then add a line to your `CLAUDE.md` so the session reaches for it without being asked:

```markdown
On an Opus or Fable session, invoke the `architect` skill before writing or
modifying code. The session model plans, briefs and reviews; it never types the
implementation. Route each slice by its shape, never by its risk tier.
```

That line matters more than it looks. A skill the model has to decide to load is a skill it mostly will not load.

## What is in here

| File | What it is |
|---|---|
| `SKILL.md` | The skill: division of labor, the brief template, the routing table, context hygiene, the review loop |
| `agents/sonnet-implementer.md` | The default worker. Rote work, briefed backend work, frontend work with an existing design grammar, shared-API-surface changes |
| `agents/opus-implementer.md` | For slices whose difficulty is in the reasoning, chosen up front and never as a retry |
| `agents/opus-implementer-xhigh.md` | The same, at xhigh effort, for concurrency, security-sensitive paths and tricky algorithms |
| `hooks/architect-guard.sh` | Optional. Raises a permission prompt when the main loop edits a source file on a Fable session |

## The brief

Everything the pattern rests on. A brief carries decisions, not options: if you are still weighing two approaches, you are not ready to delegate.

```
## Implementation brief: <slice>
Goal: one sentence, observable outcome
Context: what exploration found: excerpts, the pattern to mirror, line anchors, gotchas
Files: paths to create/modify, exclusive ownership for this slice
Design: the decided approach: data flow, names, signatures, edge cases
Constraints: project rules that apply: style, layers, security
Out of scope: what not to touch, including files owned by other slices
Verify: exact commands and expected outcome
```

The worker starts with an empty context window. Anything not in the brief it has to rediscover or guess, and rediscovery is what the pattern is trying to stop paying for.

## Routing

By shape, never by risk tier.

| Slice shape | Worker |
|---|---|
| Rote and fully decided: bulk rename, find/replace, boilerplate, generated-code touch-up | `sonnet-implementer` |
| Backend work against a detailed brief with tests to satisfy | `sonnet-implementer` |
| Frontend work that follows an existing design grammar | `sonnet-implementer` |
| Any slice that changes a shared API surface and must fix every consumer | `sonnet-implementer` |
| Genuinely hard: async correctness, a subtle multi-site refactor, a perf-critical or security-sensitive path, a non-obvious algorithm, a backfill no single test proves | `opus-implementer`, `-xhigh` for the worst |
| Design, decomposition, briefs, diff review, gates, commits, prose | the architect, in the main loop |

Risk changes how hard the diff is reviewed and who signs it off. It never changes who writes it. A high-risk path that the brief fully specifies still goes to the cheap worker, read line by line afterwards.

Two things that cost real money to learn:

- **A slice that comes back wrong is a brief problem.** Correct the same worker once. Two failures means the brief was underspecified, and a bigger model will implement the same misunderstanding more fluently.
- **A model that only executes a specification will strip an API surface without migrating its consumers.** That is why shared-surface changes go to a model that infers shape from siblings, not to the cheapest one available.

## Context hygiene, which is where the budget actually goes

Every turn re-sends the whole conversation, so anything a worker reads is paid for again on every turn after it.

- A worker never runs a full test suite. One run parks about 100 KB in context for the rest of the session. The worker runs the test files its brief names; the architect runs the gates.
- Cap turns in the agent definition. When a worker hits its cap, split the slice. Never raise the cap.
- Keep a slice under about twelve files. Split by deliverable, not by layer.
- Keep the brief under about 8 KB. One that will not fit is telling you the slice is too big.
- A moved anchor or a gap in the brief is a stop-and-report, never a licence to explore around it.

## Why this is worth doing on a subscription

If you pay per token the case is obvious: the cheaper model lists at a fraction of the expensive one, and implementation is most of the tokens.

On a Claude subscription it still holds, for a different reason. The weekly all-models limit is drawn by every token at that model's own rate, so a Sonnet worker draws it far slower than an Opus one for the same work. Fable has a separate, tighter limit that only Fable draws, so a Fable architect that never types keeps that limit for the judgment only it should be doing.

What does not work is bolting a metered third-party API onto a subscription to "save" capacity. That capacity is already paid for; a metered worker is a second bill. If you genuinely run out of worker capacity, a second subscription is the lever.

## The guard hook

`hooks/architect-guard.sh` raises a permission prompt when the main loop tries to edit a source file on a Fable session. It exempts `~/.claude`, markdown and temp directories, and it lets subagents edit freely. It is not wired up by the install above. To turn it on, add it as a `PreToolUse` hook on `Edit|Write|MultiEdit|NotebookEdit` in your settings:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit|NotebookEdit",
        "hooks": [{ "type": "command", "command": "~/.claude/hooks/architect-guard.sh" }]
      }
    ]
  }
}
```

I run without it. The skill holds because the session follows it, and the prompt gets tiresome on the small edits the skill already allows.

## Companion skill

[grain-skill](https://github.com/LivinTribunal/grain-skill) is what the worker needs on the other end: mirror the nearest existing example, and add the least that solves the problem. The architect names the exemplar in the brief; grain is how the worker uses it.

## Licence

MIT.
