# Omarchy Fleet

Read this before touching anything under `bin/omarchy-fleet*`, `bin/omarchy-profile-fleet`, `install/helpers/fleet.sh`, `install/config/fleet.sh` or `plans/fleet-*.md`, and read it before your first commit to this repository whatever you are changing.

## This repository is a fork

It is a mirror of `omacom/omarchy` carrying the Omarchy Fleet work. It is not a GitHub fork, so `upstream` has to be added by hand:

```bash
git remote add upstream https://github.com/omacom/omarchy.git
```

Two branches matter and they have different rules.

- `quattro` is a pure mirror of upstream. **Never commit to it.** It is only ever fast-forwarded from `upstream/quattro`. Keeping it clean is what makes `git log quattro..fleet-main` the exact answer to what this fork has changed, and what lets a pull request to upstream be cut from a base with no fleet content in it.
- `fleet-main` is the default branch and where every change lands. Branch from it, pull request into it.

Sync the mirror before any rebase:

```bash
git fetch upstream
git push origin upstream/quattro:quattro
```

Upstream moves fast. In the first day after mirroring, `quattro` gained a commit and the packages repository gained twenty-one.

## Branches that must stay clean

Some work here fixes a defect in upstream's own code or documentation and is meant to be offered back. Those branches are cut from `quattro`, never from `fleet-main`, so they carry no fleet content and can become an upstream pull request unchanged. `fleet/document-live-session-tests` is one. Merging such a branch into `fleet-main` is fine and does not dirty the branch itself. Rebasing it onto `fleet-main` would ruin it.

## What exists, and what does not

Phase 0 is built and merged. A machine can record that it is centrally managed, and report what it recorded. That is all it does.

- `/etc/omarchy/fleet.conf` is the enrolment record: where configuration comes from, the fingerprint of the key that must sign it, what this host is called there, what it is for, and how much of the user's configuration the fleet owns. It is world-readable on purpose and holds no secrets.
- `bin/omarchy-profile-fleet` is the predicate. A machine is enrolled exactly when the record exists and names a `config_url`. Absence of the file is a complete answer.
- `bin/omarchy-fleet` has `status`, `enroll` and `leave`, and dispatches anything else to `omarchy-fleet-<name>`, so a provider is a new binary rather than an edit to that file.
- `install/config/fleet.sh` enrols at install time from `OMARCHY_FLEET_*` in the environment, and does nothing at all when none is set.
- `install/helpers/fleet.sh` is the shared reader and writer.

There is no provider. Nothing reads a configuration repository, nothing verifies a signature, nothing reconciles, nothing runs on a timer. Enrolling a machine changes nothing about that machine. Do not describe it as though it does, in code comments, in command output or to a user.

Unverified, and needing a booted machine rather than a container: that the menu entry appears only on an enrolled machine, and that the record survives a factory reset through the `@factory` snapshot.

## Read the plans first

`plans/fleet-enrolment.md` and `plans/fleet-agent-configuration.md` are the design record, in the shape of `plans/kids-passwords.md` from the kids mode work. They carry the scope, the model, the rejected approaches with their reasons, the threat model and the open questions. A change that contradicts one of them is either a mistake or a decision that belongs in the plan first.

## Testing, and one hazard that will surprise you

Run the file for the area you changed. For fleet work that is:

```bash
bash test/shell.d/fleet-test.sh
./test/cli
```

Both are fast and touch no Wayland session. Every case in the fleet suite runs against a scratch record, so the suite writes nothing under `/etc`.

**Do not run `./test/shell` or `./test/all` on a machine you are using.** Sixteen files under `test/shell.d/` are gated on a reachable compositor and fourteen of them launch a real Quickshell against it. On a workstation that is the session you are sitting in, and the run will draw second bars, panels, overlays, tray menus and lock surfaces across the screen for its duration. Nothing persists and the running shell is not restarted, but it is alarming and it is not what the documentation implies. Use a virtual machine, or a host with no compositor reachable, where every one of them skips. `docs/testing.md` says this too, in the section on compositor-dependent tests.

To exercise the command as real root without a virtual machine, a container is enough and is how the current behaviour was verified:

```bash
docker run --rm -v "$PWD:/omarchy:ro" archlinux:latest \
  bash -c 'export OMARCHY_PATH=/omarchy PATH=/omarchy/bin:$PATH; omarchy-fleet status'
```

## House style still applies

Everything in `AGENTS.md` holds here unchanged, and three of the repository's own suites enforce parts of it that are easy to trip: no raw `command -v` or `notify-send` anywhere in `bin/`, and no heredoc with an unquoted delimiter writing under `/etc` when the body expands a variable a user can influence. The comment block at the top of `test/shell.d/privileged-heredoc-test.sh` is the best short explanation of that last rule in the tree.

Two further conventions specific to this work.

Values written into the record can contain slashes, because one of them is a git URL. Never rewrite a key with `sed`, whose replacement expression would mangle it. The helper uses `awk` with the value passed as a variable, and the test covers a URL full of slashes and ampersands for exactly this reason.

Anything committed here has to stand on its own for a reader who has never seen this project's internal notes. No shorthand reference codes, no internal host names, no pointers to private records.
