# Plan: Fleet enrolment, phase 0

Revision 1, 2026-09-11. Phase 0 of Omarchy Fleet, a fleet configuration capability built as profile-gated features inside this tree. This phase adds no management and changes no behaviour. It gives a machine one honest, readable answer to "who manages you, from where, and as what", and a command that reports it. Everything that acts on that answer is phase 1 and later.

Written against `quattro` at `b5589faaf`, and against the kids mode branch (`omacom/omarchy` PR #9750) where it is named, since that branch introduces the profile machinery this plan sits beside.

## Direction

Unlike kids mode, nobody upstream asked for this. That is the governing fact and it shapes three things:

1. Every path must be worth running in a fork on its own, because the upstream merge may never come.
2. Every file should be shaped as though the merge will come, because the cost of doing so is near zero and the cost of retrofitting is not.
3. Nothing here may change the behaviour of a machine that is not enrolled. An unenrolled Omarchy install must be byte-identical in behaviour to one without this code.

The ambition is a future pull request adding a general enrolment capability, not fleet management for one person's setup. Phase 0 is the part of that most likely to be acceptable on its own: a machine can record that it is managed, and say so.

## Problem

Omarchy assumes one machine and one owner at the keyboard. Kids mode is the first crack in that: it adds a second authority, the parent, and records the fact in `/etc/omarchy/profile`. It assumes both parties are in the same house.

An organisation, a school or a family with more than one machine needs something kids mode does not provide and cannot be stretched to provide:

- The authority is remote. An administrator is at the other end of SSH or, more often, at the other end of a git push, and is never at the keyboard.
- The configuration is shared. Many machines take their settings from one place, and that place must be a thing a machine can name.
- The machine must be able to say what it is for. A point of sale terminal, a kitchen display and a manager's workstation run the same operating system under different policy, and the difference has to live in data rather than in each machine's hand-edited config.
- A machine can be two things at once. A school laptop is a child install and a managed install. Kids mode's profile marker holds one word validated against a closed list, so a third value would make that combination unrepresentable.

None of this needs an agent to be useful. Before anything reconciles, a machine needs an enrolment record: where its configuration comes from, which key signs it, what this host is called in that configuration, and what it is for. That record is the whole of phase 0.

## Phase 0 scope

In:

- `/etc/omarchy/fleet.conf`, the enrolment record, `key=value` lines, world-readable, documented in place, absent on an unenrolled machine.
- `bin/omarchy-profile-fleet`, the predicate every later guard keys on, in the `profile` group kids mode introduces.
- `bin/omarchy-fleet` with `status`, `enroll` and `leave`, plus the feature-command dispatch later phases plug into.
- `install/helpers/fleet.sh`, the shared writer, modelled directly on kids mode's `install/helpers/parent.sh` and using the same staging and locking discipline.
- `install/config/fleet.sh`, the install leaf, so an ISO can enrol a machine at install time from environment the installer sets.
- One menu entry, `Setup > Fleet`, guarded on the predicate, running `omarchy fleet status`.
- Docs: `docs/file-layout.md`, `manual/48-security.md`, and the agent skill.
- Tests under `test/shell.d/`.

Out, for later phases:

- Every provider. Nothing reads the config repo, clones it, verifies it or applies anything.
- The root and per-user reconcile agents, their timer, and any systemd unit.
- The `shell.json` three-way merge.
- The curated plugin set and its scanner.
- ISO enrolment through the cidata payload. Phase 0 enrols by hand or through the install leaf's environment; the installer question comes with phase 1, when there is something for enrolment to do.
- Any user config mode enforcement. The record carries the declared mode; nothing acts on it.

## The model

**One file, and its absence is the answer.** Kids mode needs a separate marker because the installer must record a profile even for a default install, so that a missing marker means only "installed before profiles existed". Fleet has no such need. A machine is enrolled exactly when `/etc/omarchy/fleet.conf` exists and parses. No file means not enrolled, which is a complete answer and not an ambiguous one.

**Separate from the install profile, deliberately.** `/etc/omarchy/profile` keeps its two values and this plan does not touch it. A machine can be `profile=child` and fleet-enrolled at the same time, which is what a school needs. The two predicates compose in an ordinary menu guard, `omarchy-profile-child && omarchy-profile-fleet`, because guards are shell expressions and kids mode already combines two with `&&`.

**The record names, it does not hold.** `fleet.conf` carries a config repository URL, a signing key fingerprint, this host's identifier in that configuration, its declared roles and its user config mode. It carries no key material, no token and no credential, and it never will. It is world-readable on purpose, because everything in it is a fact about this machine that any user of this machine can already discover.

**Enrolment is a claim, not a trust decision.** The record says where this machine believes its configuration comes from. It proves nothing. The trust boundary is signature verification against a shipped keyring, and it arrives with the code that first reads the repository, in phase 1. Phase 0 must not imply otherwise anywhere in its wording, because a status command that says "enrolled" next to a URL reads like an endorsement of that URL if the copy is careless.

**Roles are declarations about this host.** A role is a word this host claims, such as `kiosk` or `backup-target`. It is not topology. The host says what it is; nothing here says what any other host is, and nothing here lists another machine. That is what keeps the record safe to leave world-readable, and it is the same separation that keeps host inventory out of the code repositories entirely.

**The user config mode is recorded and not enforced.** `managed`, `delegated` or `free`, defaulting to `delegated`. Phase 0 writes it, reports it, and does nothing with it. Recording it now means phase 1's providers read a field rather than inventing one, and it means an operator can see what a machine intends before anything can act on that intent.

## Rejected approaches

- **A third value of `/etc/omarchy/profile`.** One line of change, and it makes a child install that is also fleet-managed impossible to express, because the value list is closed and holds one word. Rejected on the school case alone.
- **A profile field holding a list.** The general answer, and the wrong time for it. Fourteen files on the kids mode branch read that marker, its validator accepts one word, and changing the type of a file while the branch that introduces it is still unmerged means conflicting with work in flight for a benefit phase 0 does not need. Revisit only if upstream asks for it while reviewing a fleet pull request.
- **A separate marker file plus a separate settings file.** Two files where one does, following the letter of kids mode's shape rather than its reason. The marker exists there to disambiguate absence, and fleet has no ambiguity to resolve.
- **JSON or TOML for the record.** `key=value` matches `parent.conf`, is readable by a shell predicate without a parser, and survives being read by an agent, a script and a person. The config repository is where structured data belongs, and this file is not that.
- **Enrolling through the installer in phase 0.** The installer question is cheap to add and impossible to test honestly while nothing consumes the answer. It waits for phase 1, when a machine that enrols at install time actually does something with the record.
- **A systemd unit in phase 0.** A timer with nothing to reconcile is an empty promise on a machine, and it is the part most likely to draw a hard no upstream. Nothing in this phase runs unattended.

## Threat model, stated plainly

- **Defends against nothing yet.** Phase 0 adds a record and a reader. It grants no privilege, takes none away, and runs nothing on a timer. Saying so here is the point: the first thing a reader of this file wants to know is whether enrolment is a security control, and in phase 0 it is not.
- **What the record exposes.** Any local user can read `fleet.conf` and learn the config repository URL, the signing key fingerprint, this host's identifier and its roles. That is the intended exposure. A URL and a fingerprint are not secrets, a host knowing its own name is unavoidable, and a user of a managed machine finding out that it is managed is a feature.
- **What the record must never hold.** Key material, tokens, passwords, and any fact about another machine. The first three are in scope for phase 1's key handling and belong under `/var/lib/omarchy/fleet/` with restrictive modes, if they belong on the machine at all. The fourth is the topology leak the whole two-repository split exists to prevent.
- **Writes are root-only.** `/etc/omarchy/fleet.conf` is mode 644 owned by root, written only through `omarchy-fleet` running as root, which stages, validates and renames atomically. A local user can read it and cannot change it. On an unenrolled machine an attacker with root could write one, which tells us nothing, since an attacker with root has already won.
- **Not defended, and named so it is not forgotten.** A machine that is enrolled and cannot reach its configuration is indistinguishable, in phase 0, from one that is up to date, because nothing checks. `status` must say when it last verified anything, and in phase 0 the honest answer is "never".

## Naming

| Thing | Name |
| --- | --- |
| Enrolment record | `/etc/omarchy/fleet.conf`, `key=value`, mode 644, absent when not enrolled |
| Predicate | `bin/omarchy-profile-fleet` (exit 0 when enrolled), group `profile` |
| Control command | `bin/omarchy-fleet`, run as `omarchy fleet <subcommand>`, group `fleet` |
| Subcommands | `status`, `enroll`, `leave` |
| Feature commands | `bin/omarchy-fleet-<feature>`, reached as `omarchy fleet <feature> ...` |
| Shared helper | `install/helpers/fleet.sh` (`install_fleet_conf`, `fleet_conf_get`, `fleet_conf_set`, `fleet_conf_document`) |
| Install leaf | `install/config/fleet.sh` |
| Install-time environment | `OMARCHY_FLEET_CONFIG_URL`, `OMARCHY_FLEET_SIGNING_KEY`, `OMARCHY_FLEET_HOST_ID`, `OMARCHY_FLEET_ROLES`, `OMARCHY_FLEET_USER_CONFIG` |
| Local state, later phases | `/var/lib/omarchy/fleet/` |
| Record keys | `config_url`, `signing_key`, `host_id`, `roles`, `user_config` |

## Design: omarchy

### 1. The enrolment record

`/etc/omarchy/fleet.conf`, one `key=value` per line, comments explaining each key in place, written only by `omarchy-fleet`. Five keys in phase 0:

- `config_url`: the git URL of the fleet configuration repository. Required. Recorded verbatim, never fetched.
- `signing_key`: the fingerprint of the key whose signatures will be required before anything is applied. Required, and unused in phase 0. Requiring it now means no machine is ever enrolled without one, which is the only way the phase 1 default of refusing unsigned configuration can be honest.
- `host_id`: this host's identifier inside that configuration. Defaults to the system hostname when not given.
- `roles`: space-separated words this host claims. May be empty.
- `user_config`: `managed`, `delegated` or `free`. Defaults to `delegated`.

Validation on write: `config_url` non-empty and matching a git URL shape, `signing_key` non-empty, `user_config` one of the three words, `host_id` and each role matching `[A-Za-z0-9._-]+`. A record that fails validation is never written, and the file that exists is always one that parses.

### 2. `install/helpers/fleet.sh`

Sourced after the caller defines `fail`, exactly as `install/helpers/parent.sh` is on the kids mode branch, and following its implementation closely rather than approximately. The parts that matter are the ones that file learned the hard way:

- Stage into the target directory so the final rename is atomic, and give the stage file a dot-prefixed name.
- Hold one persistent sibling lock file from the first existence or key check through the final rename, so documenting a default cannot overwrite a concurrent explicit choice. That race was found live on the kids mode branch on 2026-09-10 and fixed there; there is no reason to rediscover it.
- Readers take no lock, because they see either the complete old file or the complete new one.
- `fleet_conf_document KEY DEFAULT COMMENT...` writes a commented default the first time and leaves an explicit choice alone.

If kids mode merges first, consider whether the two helpers should become one shared `install/helpers/conf.sh` with `parent.sh` and `fleet.sh` as thin callers. That is the right end state and the wrong first move, because it edits a file in an unmerged branch.

### 3. `bin/omarchy-profile-fleet`

Metadata `# omarchy:summary=Succeed when this machine is enrolled in a fleet`, group `profile`, a quiet exit-code predicate in the `hw-` tradition. It succeeds when `/etc/omarchy/fleet.conf` exists and `config_url` is non-empty, and fails otherwise. Honours `OMARCHY_FLEET_CONF` so tests can point it at a scratch tree.

`GROUP_DESCRIPTIONS[profile]="Install profile detection"` already arrives with kids mode. If this lands first, add it here and let the kids mode rebase drop the duplicate.

### 4. `bin/omarchy-fleet`

Metadata `# omarchy:summary=Fleet enrolment and status`, `# omarchy:args=<status|enroll|leave> [options]`, `# omarchy:examples=omarchy fleet status | sudo omarchy fleet enroll --config-url URL --signing-key FPR`. `GROUP_DESCRIPTIONS[fleet]="Fleet enrolment and management"`.

`status` needs no root and no network. It prints whether this machine is enrolled, and when it is, the five recorded values, plus a line saying that nothing has verified or applied the configuration, because in phase 0 nothing can. When the machine is not enrolled it says so and exits 0, since not being enrolled is a normal state and not an error.

`enroll` requires root and re-execs itself under `sudo` when it is not, forwarding the caller's `GUM_*` styling the way `omarchy-system-factory-reset` does. It takes `--config-url`, `--signing-key`, `--host-id`, `--roles` and `--user-config`, validates every value before writing anything, and writes the record through the helper. Run against an already-enrolled machine it updates the named fields and leaves the rest, and prints what changed. It is idempotent: the same arguments twice change nothing the second time.

`leave` requires root, removes the record, and says what it removed. It is the reversal of `enroll` and nothing more. In later phases it must also stop the agents and say what it is leaving behind on disk, which is a good reason to have the verb exist from the start rather than adding it once there is state to strand.

Anything that is not `status`, `enroll` or `leave` dispatches to `omarchy-fleet-<name>` when such a command exists, so later phases add a provider or a feature by adding a binary rather than by editing this file. `--help` lists the feature commands it finds by their `omarchy:summary`, skipping hidden plumbing.

Outside the fleet profile, `status` reports honestly and every other subcommand except `enroll` refuses with an explanation.

House style, which the kids mode branch is currently failing on two counts and this one should not: no raw `command -v` (`bin-style-test.sh` refuses it, use `omarchy-cmd-present`), no raw `notify-send` (use `omarchy-notification-send`), and every heredoc writing under `/etc` must have a quoted delimiter (`privileged-heredoc-test.sh` refuses otherwise, and its comment block explains the class of bug it exists to catch).

### 5. `install/config/fleet.sh`

A new leaf, wired into `install/config/all.sh` with one added line after `parent.sh` when that exists, otherwise after `lockscreen-pam.sh`. When `OMARCHY_FLEET_CONFIG_URL` is set it calls `omarchy-fleet enroll` with the values from the environment; when it is not set it does nothing at all. That is the entire leaf, and it is deliberately the same shape and roughly the same length as `install/config/parent.sh`.

The environment is how an ISO enrols a machine at install time without this plan touching the installer. Phase 1 adds the cidata fields and the installer question that set those variables; until then the variables can be set by hand for testing, which is also how the shell test drives it.

### 6. Menu

One entry, `"setup.fleet": {"icon":"","label":"Fleet","when":"omarchy-profile-fleet","action":"omarchy-launch-floating-terminal-with-presentation 'omarchy fleet status'"}`. It is hidden on every machine that is not enrolled, which is every machine today, so the default menu is unchanged. Guards are evaluated as one batched script, so one more predicate costs one more line in that batch and no extra fork per menu open.

### 7. Docs

- `docs/file-layout.md`: the root-side orchestration list gains `fleet.sh`, and the quick reference table gains a row for gating something on fleet enrolment, beside the row kids mode adds for the child profile.
- `manual/48-security.md`: a short section saying what enrolment records, that the record holds no secrets, that any local user can read it, and that in this phase nothing is applied.
- `default/agents/skills/omarchy/SKILL.md`: one sentence that a machine may be fleet-enrolled, and that `omarchy-profile-fleet` is the predicate.

### 8. Tests

New `test/shell.d/fleet-test.sh`, sourcing `base-test.sh`:

- `omarchy-profile-fleet` against a missing file, a file with an empty `config_url`, and a valid record, with `OMARCHY_FLEET_CONF` pointed at a scratch tree.
- `omarchy fleet enroll` against a scratch tree as a fake root (`unshare --user --map-root-user` where available, the pattern `dns-sudoers-test.sh` uses, skipping otherwise): a valid record is written at mode 644, every documented key is present and commented, a rerun with the same arguments changes nothing, a rerun with one changed argument changes only that key, and each invalid value is refused before anything is written.
- `omarchy fleet status` on an unenrolled machine exits 0 and says so; on an enrolled one it prints all five values and the line saying nothing has been verified.
- `omarchy fleet leave` removes the record and is a no-op on a machine that has none.
- The concurrency case the kids mode helper's own test covers: two writers racing between a documented default and an explicit value, asserting the explicit value survives.
- `install/config/fleet.sh` does nothing with no environment set, and calls `enroll` with the right arguments when it is.

`./test/cli` picks up the new commands' metadata and the `fleet` group listing on its own. Run `./test/all` before proposing anything, and read the failures the kids mode branch is carrying as a warning: this repository's style suites are ordinary members of `test/shell.d/` and nothing runs them for you on a pull request.

## Design: omarchy-iso

Nothing in phase 0. The installer is untouched, the configurator asks no new question, and no field is added to `user_configuration.json`.

Phase 1 needs three things there, recorded now so the shape is not a surprise: a `fleet` block in `user_configuration.json` carrying the five values, the orchestrator passing them through to `omarchy-apply-system` as the `OMARCHY_FLEET_*` environment the leaf reads, and `omarchy-cidata-load` needing no change at all, since the fields live inside a file it already copies. The `omarchy fleet iso` command that writes such a drive from a fleet configuration repository is further out still.

One dependency worth stating: the ISO builder needs the fleet package in its offline mirror before any of this installs. That is already solved, by the one-list change on `fleet/generalise-local-packages`, which makes it `OMARCHY_EXTRA_PACKAGES=omarchy-fleet` rather than an edit to four places.

## Sequencing

Each step is one atomic commit with its tests, following the repository's own rule that commits are atomic and messages are succinct.

1. `install/helpers/fleet.sh` and `bin/omarchy-profile-fleet`, with the predicate and helper tests. Nothing else references them yet.
2. `bin/omarchy-fleet` with `status`, `enroll` and `leave`, the `fleet` group entry, and the command tests.
3. `install/config/fleet.sh` and its one line in `install/config/all.sh`, with the leaf test.
4. The menu entry, the docs and the skill sentence.

Steps 1 through 3 are independently useful and independently revertable. Step 4 is the only one that changes anything a user sees, and only on an enrolled machine.

Verify by enrolling a test VM by hand, confirming `omarchy fleet status` reports correctly, and confirming the menu entry appears there and on no other machine.

A factory reset is two cases and they give opposite answers, so a single instruction to check it is a trap. `omarchy-system-factory-reset` swaps the running `@` for a fresh clone of `@factory`, and the installer takes that snapshot as the last phase of the install, after `omarchy-apply-system --first-install` has already run `install/config/all.sh`. A machine enrolled at install time from `OMARCHY_FLEET_*` therefore has its record inside the snapshot, and a reset restores it. A machine enrolled by hand afterwards writes the record into `@` after the snapshot was taken, and a reset erases it along with every other change made since installation, which is what the command's own header says it does.

Verified on a booted VM: a machine enrolled by hand came back from a factory reset with no record and no `/etc/omarchy` directory at all. Verify the install-time case by enrolling at install time, and expect the hand-enrolled case to lose the record rather than keep it.

## Open questions

1. **Whether `signing_key` should be required in phase 0.** Requiring it means no machine is ever enrolled without one, which is the only way phase 1's refuse-unsigned default stays honest. It also means phase 0 cannot be demonstrated without inventing a fingerprint. Recommended: require it, and let the demo invent one, because the alternative trains people to enrol without it.
2. **Whether `leave` should archive the record rather than delete it.** Keeping a copy under `/var/lib/omarchy/fleet/` would help an operator work out what a machine used to belong to. It also leaves a URL and a host identifier on a machine that has been deliberately unmanaged, which may be exactly what someone wanted removed. Unresolved.
3. **Whether roles belong in the record at all in phase 0.** Nothing reads them, and a field nothing reads can drift from whatever phase 1 actually wants. The argument for keeping it is that a machine's purpose is the thing an operator most wants to see in `status`, and an empty list is a fair default. Leaning toward keeping it.
4. **The relationship between `host_id` and the hostname.** Defaulting to the hostname is convenient and makes the common case invisible. It also means a hostname change silently changes which configuration a machine believes applies to it, once phase 1 reads the repository. Recommended: default to the hostname at enrolment time and write the resolved value into the record, so it is pinned rather than derived.
5. **Whether the two `install/helpers/*.sh` writers should be merged.** Yes eventually, no while kids mode is unmerged. Revisit after PR #9750 lands or is closed.
