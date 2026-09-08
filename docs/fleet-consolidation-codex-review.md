# Peer review of fleet-consolidation direction — codex gpt-6-astra

Date: 2026-09-08. Reviewer was given the direction brief only (no repo access)
to keep the perspective decorrelated. Numbered answers map to the questions in
the brief. Companion to `docs/fleet-consolidation.md`.

1. Where Claude is wrong or self-serving

The strongest overreach is “LLMs make hand-rolled systems cheap.” They make code generation cheap, not specification, testing, compatibility, recovery, or institutional memory. Agents can also multiply locally plausible conventions—the exact reason service placement became unknowable.

The pets/cattle split is broadly sound, but “new/reinstalled boxes get NixOS” is too passive. If service mobility matters now, nominate two service hosts and migrate deliberately. Otherwise NixOS remains permanently deferred.

Rejecting Home Manager everywhere may also be an overcorrection. Full HM adoption is probably poor value, but a small pilot could still prove whether it helps with package ownership, activation ordering, rollback, and cross-machine consistency. Don’t decide ideologically; test one bounded configuration.

“One user-tool manager” is a good policy, but mise cannot honestly own everything. Some tools need system libraries, privileged integration, GUI packaging, kernel support, or timely packaging unavailable through mise. The durable rule is not “mise owns all”; it is “each artifact class has exactly one designated owner,” enforced mechanically.

2. Is `services.toml` right-sized?

A placement map is right-sized. A renderer that pretends to be a scheduler is not.

Keep `services.toml` deliberately boring:

- service identity and assigned host
- implementation/module reference
- state paths and storage class
- secret references
- ports, dependencies, health check
- backup and restore procedure
- migration constraints

Do not add automatic scheduling, failover, resource bin-packing, overlay networking, service discovery, or distributed locking. That is the road to bad Nomad.

Also, “edit one line + move data” is too glib. Safe relocation requires stop/quiesce, backup, transfer, ownership translation, validation, cutover, health verification, DNS/proxy changes, and rollback. Encode a migration runbook or command per stateful service. Stateless services may genuinely be one-line moves; stateful ones are workflows.

Avoid rendering NixOS and native systemd from one overly generic intermediate model. Their semantics differ. Share placement and metadata, but let each service provide native implementations where needed.

3. Is tiny Home Manager a trap?

Yes, if it becomes a general configuration framework. Probably not, if it stays a narrow fleet applicator.

Year-two failures will be:

- unclear activation ordering and partial failure
- inability to distinguish “managed” from merely discovered files
- destructive reconciliation after schema changes
- weak rollback and no record of the last known-good generation
- OS/version-specific conditionals spreading everywhere
- secret material leaking into logs, stores, diffs, or rendered files
- ownership/mode drift and privilege-boundary problems
- stale artifacts no longer declared but never safely removed
- package-manager races and PATH shadowing
- agents adding new abstractions instead of following one schema
- observer and applier disagreeing about canonicalization
- tests covering rendering but not real activation and recovery

Put a hard boundary around it: files, links, package ownership assertions, service enablement, and observation. No embedded programming language, dependency solver, package builder, or generic module system.

Add transactional generations: render into a versioned directory, validate, atomically switch links, retain prior generations, and support rollback. Without that, you are rebuilding the least interesting parts of HM while omitting its most valuable operational property.

4. What remains unfixed?

Repo scope remains muddled. A placement manifest and renderer do not resolve ownership among home config, fleet policy, service definitions, secrets, and agent configuration.

Secrets are barely addressed: “secret refs” says nothing about provisioning, rotation, revocation, host identity, recovery, or preventing evaluation-time leakage on NixOS.

The proposal also lacks:

- backups and tested restores
- host bootstrap/reinstallation
- decommissioning and garbage collection
- package-owner enforcement
- dependency and vulnerability updates
- schema/version migrations
- authoritative inventory of current services
- acceptance tests proving a machine converged correctly

Replacing submodules with a bespoke fetch script may simply invent an inferior package manager. Prefer existing lockfile-capable managers or packaged archives; use a custom fetcher only for irreducible cases.

5. What I would cut, add, and do first

Cut the cross-platform “one declaration renders everything” ambition. Keep one inventory and placement map, but permit separate NixOS and systemd implementations. Cut the universal mise claim and the custom fetcher as default.

Add explicit invariants:

- one declared owner per artifact
- every stateful service has backup, restore, migration, and rollback definitions
- apply is transactional
- removal is explicit and conservative
- drift checking uses the same normalized desired-state model as apply
- agents may extend only versioned schemas with validation and tests

The highest-leverage first move is not installing NixOS. Build an authoritative artifact-and-owner inventory from the existing observer manifest, then make CI reject duplicate ownership and undeclared service artifacts. That attacks the recurring conflict, exposes the real fleet topology, and supplies the migration backlog. Only after that, move one low-risk service onto one NixOS host and prove deployment, backup, restore, relocation, and rollback end to end.
