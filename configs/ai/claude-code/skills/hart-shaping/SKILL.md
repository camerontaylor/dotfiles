---
name: hart-shaping
description: The hart definition-step burst - opens with a plain-language orientation brief, forks shape/close/park/split, then a short scoping conversation that turns a fuzzy item into a card (About, Done, Tier, First move, plus Tail, Obstacle, Not doing) or an evidence-argued disposition. Use when Cameron says "shape X" or "scope X" in any chat, or accepts a shape offer. Writes the result back to triage/proposals.md or triage/shaping/.
metadata:
  version: "1.1.0"
  emoji: "⌇"
  tags: ["adhd", "definition", "shaping", "hart"]
---

# hart-shaping — the burst-conversation contract

Canonical copy: `/home/ctaylor/repos/hart/skills/hart-shaping/`. Wesley's and Claude Code's are installs — edit here, re-sync with `--force` (§11). Design: `docs/definition-step-design.md`.

**The conversation is the product; the card is only its residue.**

## 1. Invocation, orientation, fork
Triggers: "shape X", "scope X", or an accepted shape offer. A loose reference ("the trust thing") resolves against `triage/queue.md` → `triage/proposals.md` → Linear, in that order. **Confirm which item you heard before asking anything else.**

**Orientation brief (always, before any question).** Cameron arrives cold — he interrupt-slices across parallel agent threads, and he may only ever have half-known the item's referents even at capture time. Open with a short plain-language brief, cited: what this item is, where it came from, what has already been decided, what is genuinely open. Gloss every id or codename on first use ("R6 — the open question of whether skills keep separate references/ files"). **A referent you cannot resolve from the repo is surfaced as unresolved** ("I can't establish what X6 was from the source line — that's question 1"), never smoothly paraphrased: the citation hard rule extends to referents. The brief is also his grounding — it is what stops *him* piecing the item together from insufficient context.

**Disposition fork (one question, right after the brief).** Not every accepted prompt wants shaping — some want to find out what the item was for and whether it can end. So the first question is the fork: **shape it / close it / park it / split it**, with your evidence-backed recommendation. Argue the recommendation from verified evidence (the python-dep-manifest precedent: closed on a live audit of all 16 scripts, not on staleness vibes) — closing must never become the low-friction default. Only "shape" enters the frontier rounds; close/park/merge land as a disposition card (§9).

## 2. Frontier rounds
Ask **every currently-answerable question in one numbered round** — not one at a time. A question is currently-answerable when no other unanswered question could change it. His answers unlock the next frontier; repeat until the floor (§5) clears. **You research the facts yourself** — the item's own text and history, Linear, the court mirror — and never ask him something the repo can tell you. He only decides. Lead each round with one line of what you found, so the choices are grounded. **Re-entry header:** every round after the first opens with 1–2 lines of where-we-are — the item in plain words, what's decided so far, what this round settles. Each round is an interrupt boundary in Cameron's threading model; any round must be re-enterable cold, ids glossed on first use.

## 3. Question rendering, per surface
Every question carries **2–4 distinct options, a marked recommendation with one line of why, and free text as an escape hatch.** Reply cost: one number or word.
- **Claude Code, or any surface with a native ask tool: always use `AskUserQuestion`.** Never print an options question as loose prose where a structured ask exists.
- **Discord / Telegram via OpenClaw (no ask tool):** a fixed block, queue field names — `Q:` one line · numbered options · `Recommendation:` plus one line of why · `Context:` the 1–3 facts needed to decide. **No markdown tables** (`AGENTS.md` §Local notes).
- **Clarification ≠ answer.** A reply that asks *about* the options is answered briefly and the same question re-presented. It is never recorded as progress.

## 4. Materiality
Ask only if the answer changes what gets done. If both answers lead to the same first move, don't ask.

## 5. The definedness floor
Four binary checks, run **silently** after every round. Scope is **not defined** while any of them fails:
1. a card field is empty, or agent-filled without Cameron having chosen or confirmed it;
2. an unresolved contradiction stands between two answers;
3. the item turned out to be a disguised project and an active sub-part lacks its own done + first move;
4. the *last* answer expanded scope (new noun, new party, new deliverable).

**Agent-answered ≠ defined:** an agent-guessed field never completes a card on its own; if your guesses would be what tips scope into defined, he confirms them explicitly first. **Ontology shift:** if the core noun keeps changing across answers, stop asking detail questions and ask "what IS this, really?"

Cameron sees only **"clear enough"** or **"still fuzzy on X, because Y."** No numeric scores, no ambiguity percentages, no per-round score tables — that apparatus is the homework feeling this contract exists to avoid.

## 6. Checkpoint offers
At each natural checkpoint (~4–5 questions, or when the floor clears): **"Write the card, or keep sharpening?"** Continuing is opt-in; stopping is honest about what is still fuzzy. **No cap ever acts as a cutoff.**

## 7. Dialectic rhythm guard
After 3 consecutive agent-resolved steps, the next decision goes to Cameron whether or not you could have answered it yourself. The interview is with him, not with `context.md`.

## 8. Restate gate
Collapse everything agreed into **ONE sentence**, display it verbatim, and ask: *"If you read only this line later, would you do the thing you mean now?"* Three options: **yes, write the card** / **adjust wording** / **something's missing**. **Two loops maximum.** The confirmed sentence **is** the card's Done line.

## 9. Card write-back
- **Continue, never restart.** Before asking anything, read any existing card block for the item — `triage/shaping/<id>.md` **first**, then the item's `triage/proposals.md` entry. Continue a half-dripped or half-shaped card, preserving every field and `choice:` marker already recorded. Set `source:` to `drip` when continuing a drip card.
- **Record the option set per human-decided field**, not just the value: `choice: T2 (of T1|T2|T3, rec T2)`. An agent-filled field records `choice: agent-filled, confirmed <yes|no>`. **`confirmed no` is legal on a written card provided `Still fuzzy` is present** — that is the honest-stop path, and no write gate may close it.
- **Always show the finished card in-chat first.** Block format: `triage/shaping/README.md`.
- **Pre-issue item** → append the card block to the item's `triage/proposals.md` entry. The existing `confirmed→issued` write carries it into Linear. No new write point.
- **Already-issued item** → write `triage/shaping/<id>.md` with its `ids:` frontmatter list and exactly one `## shape <ISO>` heading. The consolidator folds it into the Linear description next run — ask for a run now if you want it sooner.
- **Disposition outcome** (fork chose close/park/merge): write a disposition card — `level:disposition`, About + Disposition + Because, cited (format: `triage/shaping/README.md`). Pre-issue item → the `proposals.md` entry; the consolidator retires the queue side next run. Already-issued item → `triage/shaping/<id>.md`; the consolidator executes the Linear state change next run (its write point 4). Either way you still never write Linear.
- **Split item** → the parts stay inside the parent card as `### Card — part <n>` sub-blocks, each with its own Done + First move (floor check 3). At `confirmed→issued` the consolidator creates the parent issue plus one sub-issue per part. Extract a part to its own top-level entry only when it is conceptually a different thing — **never for timing**.
- **Concurrency on `proposals.md` — two writers.** Before appending, re-read the file and its `Generated:` stamp (`triage/proposals.md:4`). If the stamp advanced since you read the item, re-read that item's entry and append to the current text. Never rewrite another writer's content.
- **Parallel sessions** (the paseo fan-out): one session per item, never two on the same item; never touch another item's entry or card file; `git add` only your own paths. The re-read rule above is what keeps N concurrent sessions safe.
- **Commit the write.** `git add` the touched file and commit `shaping: card <item-id>`. An uncommitted card is not durable.
- **Code-realm item** → the card *seeds* the coding pipeline: `deep-interview`/`ralplan` start from its Done/Tier/Not-doing instead of a cold idea, and the finished work is validated against the Done sentence.
- **Hard prohibition:** you write `triage/proposals.md` and `triage/shaping/`, and nothing else. **Never `triage/queue.md`. Never `triage/plan.md`. Never Linear.**

## 10. Do not refactor this ritual into a form
The documented failure mode is an instance "helpfully streamlining the ritual back into a form you fill out alone" (`docs/definition-step-design.md:21`); solo authorship fails for Cameron on the record — *"Voluntarily create a plan/definition that resolves ambiguity? Anathema"* (`docs/completion-scaffold-ritual.md`, §Implementation finding; chat `7a6258fd`, msg `01a0112e-195c-7939-9afa-1541b544950a`). §9's option-set records are an **audit hook** that makes the P6 transcript review falsifiable, and nothing stronger: a conforming agent that ran a form could write conforming markers.

## 11. Distribution — three copies, one canonical
Harmony needs no install (its OpenClaw workspace *is* this repo). The other two drift unless re-synced with `--force` — the known failure mode, `repo-research` already exists as two copies.
- Wesley: `openclaw skills install /home/ctaylor/repos/hart/skills/hart-shaping --agent wesley --force`
- Claude Code: `cp -r /home/ctaylor/repos/hart/skills/hart-shaping ~/.claude/skills/`

claude.ai is out of scope: no filesystem write-back path, so §9 is unexecutable there. Land its cards through the Linear `inbox` capture channel instead (`skills/hart-consolidator/SKILL.md:41`), drained at step 1.5.
