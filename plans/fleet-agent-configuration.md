# Plan: Fleet agent configuration

Revision 1, 2026-09-11. The phase after enrolment. `plans/fleet-enrolment.md` gives a machine a record of where its configuration comes from; this plan is the first thing that configuration carries, and it is deliberately not the desktop.

Written against `quattro` at `b5589faaf`. Nothing here is built.

## Direction

Every machine in a fleet runs coding agents, and what those agents are told shapes what happens on that machine every day. An organisation that can set a wallpaper across fifty machines but cannot set what its agents do with a production database is managing the least consequential surface it owns.

That is the argument for doing this before the desktop providers, and it is also the argument for being careful, because the same reach that makes it worth building makes it the most dangerous thing the configuration repository will carry.

## Problem

Agent configuration today is per machine and per person. Someone writes an instruction file, copies it to a second machine by hand, and the two drift apart the same afternoon. A team that agrees on a practice has no way to make that practice arrive anywhere. An organisation that needs one, for a compliance rule or a production system that must not be touched, has no mechanism at all beyond asking.

Omarchy already solved the hard half of the distribution problem for its own content. `bin/omarchy-provision-user` loops every directory under `$OMARCHY_PATH/default/agents/skills/` and symlinks each into six agent skill directories, `~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills`, `~/.pi/agent/skills`, `~/.gemini/config/skills` and `~/.hermes/skills`, plus every directory under `~/.hermes/profiles`. Its comment says the loop exists so that shipping a new skill needs no edit. `bin/omarchy-default-agent` writes one file and knows fourteen agents by name.

So the machinery for putting agent content in the right places on one machine exists and is maintained. What is missing is a way for an organisation to supply that content, and a way to know whether it arrived and stayed.

## The layers, ordered by what they can actually do

The single most important thing in this plan. These are not five flavours of the same thing, and treating them as one bundle produces a feature that promises control and delivers advice.

**1. Tool and permission configuration. The only enforceable layer.** Allowlists and denylists, hooks, which servers an agent may talk to, sandbox and approval settings. The harness reads these, not the model, so a value pushed here is a control in the ordinary sense: it holds whether or not anything agrees with it. If the point of this work is that agents behave consistently across an organisation, this is the layer that delivers it, and it should be built first.

**2. Instructions and system prompts.** The per-agent instruction files and their equivalents. Read every session, they steer strongly, and they bind nothing. Highest leverage per line written and no guarantee whatsoever. Worth distributing, and worth wording carefully everywhere it is described, because a status screen saying instructions are applied invites the reading that they are obeyed.

**3. Skills.** Packaged procedures loaded by name when an agent decides they are relevant. Content rather than policy, versioned, and the easiest of the five to distribute because Omarchy's own loop already places them. The least contentious and the best place to start proving the provider.

**4. Model, endpoint and credential policy.** Which model, which endpoint, which gateway. This is usually what makes an organisation care at all, because it is where cost and data residency live. Partly enforceable through configuration the harness reads, and it is the layer most likely to involve a secret, which means it is the layer that must not be in the configuration repository. See the threat model.

**5. Default agent.** One file, `~/.config/omarchy/defaults/agent`, already written by an Omarchy command. Trivial to set and worth setting, since an organisation that has standardised on one tool should not have to ask each person to pick it.

## Scope

In:

- A provider that renders an `agents/` tree from the configuration repository onto a machine, covering layers 1, 2, 3 and 5.
- A target map read from the configuration repository rather than carried in the provider, so a new agent is a data change.
- Namespacing, so fleet content never silently replaces Omarchy's shipped content or a person's own.
- A baseline and a three-way merge for any file a person also edits, on the model of the desktop configuration problem, with conflict reported and nothing applied.
- Drift reporting through `omarchy fleet status`, which is the only honest form of enforcement above layer 1.
- The three user configuration modes from the enrolment record deciding how far the provider goes.

Out:

- Layer 4's credentials. A model or an endpoint is configuration; a key is not, and the configuration repository is not a secret store.
- Any attempt to verify that an agent read what was placed. It cannot be done in general and must not be implied.
- Any change to how Omarchy places its own shipped skills. The provider works beside that loop and never inside it.
- Project-local agent files. The repository somebody is working in belongs to them, and it is also the escape valve that makes the rest of this tolerable.

## The model

**Fleet owns the global layer and never the project layer.** Agents read instructions from several places and merge them, typically something global, something per project, and something local. Fleet owns the global one. The project one stays untouched, deliberately, because a person needs somewhere to disagree and because a fleet that reaches into working repositories would be the last straw for anyone evaluating it.

**Precedence must be legible, not clever.** Two prose files that contradict each other do not resolve by ordering, whatever the load order says. So fleet content goes in its own marked file rather than being merged into somebody's, and where an agent supports only one file, the fleet block is delimited and the rest is left alone. When a local file contradicts the fleet block, the answer is to report it, not to win silently.

**Drift reporting is the product.** For layers 2, 3 and 5 the machine can honestly say: this is what the fleet sent, this is what is on disk, and here is the difference. That is worth having. What it must never say is that the instructions are in force.

**Namespacing is a correctness requirement, not tidiness.** Fleet skills land under a fleet-owned directory name so they cannot collide with a shipped skill or a personal one. Two directories claiming the same skill name, resolved by whichever symlink was written last, is exactly the failure this content cannot afford.

**The target map is data.** Six skill directories today. A different six within a year, and the list already includes one agent that needs a second pass for its profiles. A provider carrying that list in code turns every new agent into a code change and a rebase, on a fork that is trying to minimise both.

**The mode decides the reach.** `managed` means root-owned files a person cannot edit, which is the only real enforcement available for layers 2 and 3 and is appropriate on a shared terminal. `delegated` means applied and drift reported, which is right for a workstation. `free` means untouched.

## Rejected approaches

- **One bundle called "agent config".** Hides the fact that only one of the five layers enforces anything. The distinction has to survive into the command output and the documentation or the feature misleads its own operator.
- **Merging fleet text into a person's existing instruction file.** Produces a file nobody owns and a merge conflict nobody can resolve. A separate file, or a delimited block where a separate file is impossible.
- **Putting the target list in the provider.** Becomes a rebase tax and a support burden the first time an agent changes where it looks.
- **Shipping credentials alongside the endpoint policy.** The configuration repository is readable by everyone who can read it and is mirrored onto every machine. A key there is a key everywhere. Endpoints and model names are configuration; the credential arrives by another route or not at all.
- **Verifying that an agent obeyed.** Not possible in general, and an implementation that checked one agent's logs would imply a guarantee about the other thirteen.
- **Reaching into project repositories.** The place a person works is theirs. It is also the escape valve, and a fleet without one is a fleet people work around.

## Threat model, stated plainly

- **Defends against drift and inconsistency.** Fifty machines whose agents were told fifty different things, and no way to tell which. After this, one source and a report of where reality differs.
- **Does not defend against a person who does not want it.** Layers 2, 3 and 5 can be ignored, bypassed with a flag, or pointed elsewhere. Under `managed` the files cannot be edited, which is not the same as the instructions being followed. Layer 1 is the exception and is the reason it comes first.
- **The blast radius is the largest in the configuration repository.** Whoever merges into the `agents/` tree changes what every agent on every machine is told, on the next reconcile, with nobody at a keyboard. That is more consequential than the plugin set, which at least gets a scanner, and much more than the theme. Three consequences: the tree is inside the signature boundary with no exception; it needs a narrower code owner than the rest of the repository; and it is the first path where a second reviewer is worth the friction.
- **No scanner applies.** Code scanning grades diffs of code. These are prose. A skill that tells agents to skip a check, to trust a directory, or to prefer one vendor passes every gate this project currently plans. Reviewing instructions for how they will steer an agent is a different discipline and there is no tooling for it here. Naming that now is cheaper than discovering it.
- **A compromised configuration repository is worse here than anywhere else.** Elsewhere it means a wrong wallpaper or an unwanted package. Here it means every agent in the organisation acting on an attacker's instructions, on machines whose users have no reason to look at the file. Signature verification is not optional on this path, and the failure mode on a bad signature is to keep what is already there and say so loudly.
- **Not a compliance control.** An organisation may want to say that its agents are configured to a standard. This can show that files matching a standard are present on every machine, and that is all it can show.

## Naming

| Thing | Name |
| --- | --- |
| Tree in the configuration repository | `agents/` |
| Targets, as data | `agents/targets.yaml` (or the repository's chosen format) |
| Fleet skills | `agents/skills/<name>/` |
| Fleet instructions | `agents/instructions/<agent>.md`, with a shared default |
| Tool and permission policy | `agents/policy/<agent>.json` |
| Provider command | `bin/omarchy-fleet-agents`, reached as `omarchy fleet agents` |
| Namespaced skill directory on a machine | `fleet-<name>` under each target |
| Baseline for merge | `~/.local/state/omarchy-fleet/agents/` |
| Record keys it reads | `user_config` from `/etc/omarchy/fleet.conf` |

## Design: omarchy

1. **`bin/omarchy-fleet-agents`**, a feature command reached through the dispatcher, so nothing in `bin/omarchy-fleet` changes. `--dry-run` by default in the sense the wider design requires: report what would change, and apply only when told.
2. **Targets read from the tree.** Each target names a directory and what kind of content goes there. The shipped default matches what `omarchy-provision-user` already writes, so a fleet that adds nothing still lands in the right places.
3. **Skills** are copied or linked under a `fleet-` prefixed name. A name collision with a shipped skill is a reported error, never a silent overwrite.
4. **Instructions** are written as their own file where the agent supports one, and as a delimited block where it does not, with the block's boundaries stable so a rewrite is a diff rather than a replacement.
5. **Policy files** are the one layer where the provider may legitimately replace a whole file under `managed`, because a partially applied permission set is worse than either whole.
6. **Drift** is computed against the baseline the same way the desktop configuration provider will, so the two share one implementation and one set of failure semantics.
7. **Status** gains a section listing, per layer, what the fleet sent and whether the machine matches.

## Sequencing

Layer order, not file order, and each step is one atomic commit with its tests.

1. The target map and the skills layer. Least contentious, proves the provider, and skills are the content most likely to be wanted first.
2. The instruction layer, with the baseline and the merge. This is where the three-way merge gets built, on text where a bad merge costs nothing, which is the cheapest possible rehearsal for the desktop configuration file that has the same problem and much worse consequences.
3. The policy layer, which is the one that enforces, once the two easier layers have shaken out the provider's shape.
4. The default agent, which is one file and belongs last because it is trivial.

## Open questions

1. **Collision with a shipped skill.** A fleet skill named like an Omarchy skill is an error, but which error: refuse the whole apply, skip that skill and report, or namespace it away automatically. Leaning toward refuse and report, because silence is what this content cannot afford.
2. **Whether the tree layers.** Desktop configuration layers fleet, host class, host, user. Agent instructions could too. Layering is consistent and is also more rope than most organisations want on this path, since it makes the question "what is this machine's agent told" much harder to answer. Leaning toward one set per fleet with per host class as the only subdivision.
3. **Where the endpoint policy stops and the credential starts.** Naming a gateway is configuration. Naming a gateway that only works with a token pushes the token question somewhere, and this plan does not answer where.
4. **What to do about agents nobody mapped.** Fourteen are known to Omarchy and more exist. A person using an unmapped agent gets none of this and no warning. Reporting that a machine runs something the fleet does not know about needs a detection story that does not exist yet.
5. **Whether the delimited block is worth it.** Supporting agents whose instruction file cannot be split adds a parser and a class of merge bug. The alternative is to support only agents with a separate global file and say so.
