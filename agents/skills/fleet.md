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

Both of the things a container could not show have now been checked on a booted machine, and one of them did not hold.

The menu entry behaves. On an unenrolled machine the Setup menu runs Plugins straight into Security. After `sudo omarchy fleet enroll` the Fleet entry appears between them on the next open of the menu, with no shell restart, and selecting it runs `omarchy fleet status` in the floating terminal.

The record does not survive a factory reset unless it was written during the install. `omarchy-system-factory-reset` swaps the running `@` for a fresh clone of `@factory`, and the installer takes that snapshot as its last phase, after `omarchy-apply-system --first-install` has already run `install/config/all.sh`. So an install-time enrolment is inside the snapshot and comes back, and a hand-made one afterwards is erased along with every other change since installation. A machine enrolled by hand was reset and came back with no record and no `/etc/omarchy` directory at all. `plans/fleet-enrolment.md` carries the detail. Do not test the install-time case by enrolling by hand, because the two paths answer differently.

## A fleet build on a real machine loses to upstream on the first update

Testing this work on a virtual machine means building an ISO with `--local-source` against this checkout, which puts the fleet code inside the `omarchy-dev` package. That is the name upstream publishes on its edge channel, and the installed system points its `[omarchy]` repository there. The generated package version is a commit count, so this fork's build loses to upstream's whenever upstream's development branch is ahead of the branch point, which is the normal state.

The consequence, seen on two machines: one `pacman -Syu` upgraded `omarchy-dev` and `omarchy-settings-dev` to upstream's build and took `bin/omarchy-fleet`, `bin/omarchy-profile-fleet`, `install/config/fleet.sh`, the menu entry and the router's `fleet` group with them. No warning, first update after installation, and the locally built package was not left in the package cache to downgrade back to.

An enrolled machine comes off worse. The upgrade removes the command and the predicate and leaves `/etc/omarchy/fleet.conf` behind, because no package owns that file, so the machine still calls itself centrally managed with nothing left that can read the claim.

Until the fleet code ships as its own package with a name upstream does not publish, treat any machine built this way as valid only until it updates. Check the build on a machine before trusting a result from it:

```bash
pacman -Q omarchy-dev
```

A version whose hash is not a commit in this repository means the fleet code is already gone.

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
