# How the ralplan pattern is distorting planning

Date: 2026-09-08. Status: problem statement — a starting point for designing a
replacement process, not the replacement itself.

## Where the value came from

Ralplan (planner drafts → architect steelmans → critic gates → iterate) earned
its place when it was introduced. Against weaker models, the adversarial loop
caught real errors: missed constraints, unverified claims, absent rollback
stories. The structure compensated for shallow single-pass reasoning by buying
depth with process. That was diligence.

The premise has quietly inverted. Current frontier models internalize the
critique loop — they steelman and pre-mortem as part of drafting. The marginal
defect caught by a separate critic pass has collapsed, while the process cost
(iterations, verdict ceremony, consensus prose) stayed fixed. A process whose
cost is flat while its benefit decays becomes bureaucracy on a schedule.

## The case that surfaced this

`plans/ralplan-declarative-nix-fleet.md` (2026-09-07): two iterations,
architect APPROVE, critic APPROVE — and a plan whose own "Intent
reconciliation" section admits the central strategic question (what endpoint
does the owner actually want?) was never answered. Seven work packages, eight
readiness gates, a custom release-receipt format, a manifest schema version
bump with fleet-wide reader rollout — all sequenced ahead of the first live
deliverable: symlinking one bat config file. Meanwhile a manual, plain-language
collaboration between the owner and a single model produced the substantive
review (value question, sequencing inversion, concrete simplifications) in one
pass.

Also telling: this plan existed because a model (astra) saw ralplan in its
skills list and invoked it on its own initiative. Nobody decided this problem
deserved heavyweight planning; the process selected itself.

## Distortion mechanisms

1. **It optimizes for defensibility, not value.** Critic gates reward fenced
   hazards and scoped claims. No role in the loop owns the question "is this
   worth doing at all?" — so a plan can be flawless at every step and wrong as
   a whole, and the loop will approve it.

2. **Iteration ratchets scope up, never down.** Each critique round adds
   hedges, constraints, and sub-gates; reviewers are structurally rewarded for
   adding and never for deleting. Plans grow monotonically toward the shape
   that survives review, which is also the shape hardest to execute.

3. **Consensus launders confidence.** "Architect APPROVE, critic APPROVE"
   reads like independent validation, but the reviewers share training,
   context, and blind spots. Agreement among correlated reviewers measures
   internal consistency, not correctness — and definitely not value.

4. **Prose written to survive review can't be executed from.** The winning
   register is negation-dense constraint listing ("does not claim", "never
   substitutes for", "is not authorization"). Almost no sentence names a file
   to create, a command to run, or a test to write. The implementing agent
   must re-derive everything.

5. **Learning is back-loaded.** The format demands the full W0–Wn arc be
   specified before any contact with reality. Cheap probes — the
   disposable-environment experiment that would answer "do we even want this?"
   in a day — get buried as prerequisites of late work packages instead of
   being the first gate.

6. **Skill affordance becomes mandate.** A listed skill reads as an
   instruction to capability-eager models. Any process this heavy needs a
   discuss-first convention: the model proposes it and asks, it does not
   self-invoke. (Claude models happen to behave this way; the process should
   not depend on model temperament.)

7. **Effort intuitions are stale, which inflates the case for process.**
   Model priors about how long work takes are trained on pre-LLM labor costs
   (so are the owner's — their words). When re-implementation costs an
   agent-afternoon, elaborate risk amortization over "expensive" work is
   solving a price that no longer exists. Estimates remain useful relatively,
   not absolutely.

8. **Process cost is not indexed to anything.** Ralplan applies the same
   ceremony to "adopt Nix across the fleet" and to problems a tenth the size.
   A scaffold built for a weaker model becomes a cage for a stronger one; a
   process designed for irreversible changes is waste on reversible ones.

## What ralplan got right — keep these

- **Pre-mortems.** "Six months later this failed because…" is cheap and
  routinely surfaces the real risks.
- **Dated, cited evidence sections.** Point-in-time observations with
  file:line references make plans auditable and honestly perishable.
- **Explicit non-goals and kill criteria.** The best antidote to scope creep.
- **ADR capture.** Decision, drivers, alternatives, consequences — worth
  keeping in any replacement, at a fraction of current length.

## Sketch of a replacement

Principles first; the concrete process is the investigation to run.

- **The value question is answered first, by the human.** One paragraph:
  what pain, what payoff, how we'd know it worked. No plan starts without it.
  (The owner doing this early — "something I need to do more of early on in a
  process" — removes the single biggest failure mode for free.)
- **Probe before plan.** If a cheap experiment can falsify the premise, run it
  before writing anything called a plan. Plans follow evidence, not the
  reverse.
- **Plan the next irreversible step in detail; sketch everything after.**
  Detail beyond the first gate is speculation formatted as rigor.
- **Review is a peer conversation, not a verdict gate.** One reviewer, ideally
  a different model family, whose brief explicitly includes "should we do this
  at all?" and license to delete scope — measured by what they remove, not
  what they add.
- **Budget the document.** A plan that can't say its piece in ~150 lines is
  deciding too many things at once; split it or shrink it.
- **Index ceremony to reversibility × blast radius, not to habit.** Reversible
  + small = a paragraph and a go. Irreversible + fleet-wide = evidence,
  pre-mortem, human sign-off. Most work is the former.
- **The human stays in the loop as facilitator, not gate-keeper of a ritual.**
  The observed best results came from manual plain-language collaboration
  between models with the owner steering. The replacement should make that
  cheap and default, not exceptional.

## Open questions for the investigation

- What is the lightest artifact that still captures decisions durably? (ADR
  paragraph? annotated commit? a `plans/` file with a hard length budget?)
- When is a second model genuinely worth it — different family for
  decorrelation, or same family with an aggressive deletion brief?
- How should planning skills signal "propose, don't self-invoke" so
  capability-eager models don't select them by affordance?
- What replaces the APPROVE stamp as the "ready" signal — owner sign-off only?
- Does anything remain that justifies full ralplan ceremony, or is the
  irreversible-fleet-change tier better served by probe + short plan + human
  gate?
