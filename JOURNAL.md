# Journal: handoff

Last updated: 2026-09-15

> ## START HERE
>
> Phase 0 is built, merged, and now verified on a booted machine rather than only in a
> container. Read [`agents/skills/fleet.md`](agents/skills/fleet.md) before touching
> anything, and read the two plans under `plans/` before changing what phase 0 or phase 1
> is supposed to do.
>
> **Start here, and start with this.** A machine built from a `--local-source` ISO loses the
> entire fleet build on its first `pacman -Syu`, because the code ships inside `omarchy-dev`
> and upstream publishes a package by that name with a higher version. No demonstration on
> real hardware survives an update, and any test result from a machine that has updated is
> void. Check with `pacman -Q omarchy-dev` and compare the hash against this repository
> before trusting anything a test machine says. Details in the session entry below and in
> the skill.
>
> That is a diagnosis and not yet a fix, and turning it into one is the next piece of work.
> It has two halves and the second is the one nobody has answered.
>
> 1. **Write the package recipe.** `pkgbuilds/omarchy-fleet/` in the packages fork, in the
>    shape every other package there uses, taking its source from the mounted runtime
>    checkout. Shipping it is one environment variable on the ISO build, because the
>    installer fork already publishes its package list with an append point. A package by
>    that name cannot be replaced by upstream, because upstream publishes nothing by it.
> 2. **Decide where a fleet machine's runtime package comes from.** The recipe does not
>    settle this. `omarchy-dev` itself keeps losing the same race, so a fleet machine that
>    installs upstream's runtime package and this fork's fleet package still ends up running
>    upstream's code with a fleet package sitting on top of it. That question is the same one
>    as package signing and as whether a self-hosted instance can serve as an adopter's own
>    channel. Answer it before building anything that depends on a machine staying fleet
>    shaped.
>
> Do not skip to the demonstration scenarios. Every one of them needs a machine that is
> still fleet shaped after an update.
>
> **What is verified and what is not:**
>
> - Verified on a booted machine: the menu entry appears only after enrolment, and running
>   it reports the record correctly.
> - Verified and corrected: a factory reset keeps an enrolment only when it was written
>   during the install. A hand-made enrolment afterwards is erased. The plan previously
>   said the opposite and asked for a test that could not pass.
> - Not yet run: the install-time enrolment case. It needs the ISO to carry the enrolment
>   fields, which is the installer repository's next piece of work.
>
> **Commit signing is done and enforced.** Set up on 2026-09-15 and verified against a real
> pushed commit. SSH signing with the maintainer's existing key, registered on GitHub as a
> signing key, and required signatures now enabled on `fleet-main` in all three
> repositories. The mirror branches were left alone.
>
> Two consequences for anything you do next. Your commits sign automatically and you should
> check rather than assume, which `agents/skills/fleet.md` covers. And a pull request
> carrying an unsigned commit is now refused whatever the merge method, which first bites
> when a clean branch cut from a newer `quattro` is merged into `fleet-main`, because
> upstream's history is partly unsigned. That merge is the maintainer's call and not a
> thing to attempt from a feature branch.
>
> Four commits already on `fleet-main` are unsigned, including the one that introduced the
> rule. The rule landed before the key did. They are left alone on purpose.

## Session of 2026-09-15: phase 0 checked on real machines, and one finding that outranks it

Built the first ISO this project has produced, installed two virtual machines from it, and
worked through the two verification items that a container could not reach. Both are now
answered. A third thing turned up that nobody was looking for and matters more than either.

### The ISO

```bash
./bin/omarchy-iso-make --no-boot-offer --keep-pkg-cache --local-source ../omarchy-fleet ../omarchy-fleet-pkgs
```

Roughly 5.9 GiB, built from this repository's default branch, and it carries the fleet code
in the runtime package, so the separate fleet package is not needed to get a machine to test
on. Two things are worth knowing before running it again.

`--keep-pkg-cache` matters on a machine you use. Without it the script purges the build
host's own pacman cache before starting, which is the cache a rollback reads from. The flag
exists for unattended builds and skips only that step.

An autoinstall drive has to name the development packages. A build with `--local-source`
produces `omarchy-dev` and `omarchy-settings-dev`, and the ISO passes those names to its own
configurator. A cidata drive skips the configurator and carries its own package list, so a
drive that asks for `omarchy` fails late inside the installer against an offline mirror that
has no package by that name.

### The menu entry appears only when enrolled, and works

On an unenrolled machine the Setup menu runs Plugins straight into Security. After
enrolment the Fleet entry appears between them on the next open of the menu, with no shell
restart and no refresh command, and selecting it runs `omarchy fleet status` in the floating
terminal with the five recorded values and the line saying nothing has been fetched,
verified or applied. The record landed at mode 644 owned by root, and the predicate went
from failing to succeeding. That is the whole user-visible surface of phase 0 behaving as
designed on a real session.

### A factory reset erases a hand-made enrolment, and the plan said otherwise

`plans/fleet-enrolment.md` asked to confirm that a factory reset leaves the record in place.
It does not, for a machine enrolled by hand. The reset swaps the running root subvolume for a
fresh clone of the factory snapshot, and the command says so in its own header. Nothing
copies `/etc/omarchy` forward. A machine enrolled by hand was reset and came back at the
first-boot setup screen with no record and no `/etc/omarchy` directory at all.

The claim holds for the case the design actually cares about. The installer takes the factory
snapshot as its last phase, after it has already run the Omarchy configuration step that
includes the fleet leaf, so an enrolment written from the environment during the install is
inside the snapshot and comes back after a reset. The plan conflated the two cases and then
asked for the one that gives the opposite answer. Corrected in this branch.

### The first update replaces the fork's build with upstream's

Both machines were updated and rebooted. One `pacman -Syu` upgraded `omarchy-dev` and
`omarchy-settings-dev` from this repository's build to upstream's, and took `bin/omarchy-fleet`,
`bin/omarchy-profile-fleet`, `install/config/fleet.sh`, the `setup.fleet` menu entry and the
router's `fleet` group with them. No warning. Nothing fleet-shaped was left on either
machine, and the locally built package was not in the package cache to go back to.

The cause is a name collision made certain by arithmetic. A `--local-source` build puts the
fleet code inside `omarchy-dev`, the installed system points at upstream's edge channel, and
the package version is a commit count, so this fork loses whenever upstream is ahead of the
branch point. That is the ordinary state of the mirror rather than an unlucky week.

An enrolled machine comes off worse than these two did. The upgrade removes the command and
the predicate and leaves the enrolment record behind, because no package owns that file. The
machine still declares itself centrally managed with nothing left that can read the
declaration, and the menu guard becomes a missing command rather than a false one.

This is an argument for shipping the fleet code as its own package rather than against it.
Upstream publishes nothing by that name, so a separate package cannot be replaced this way.
What is not yet decided is where a fleet machine's runtime package comes from, which is the
same open question as package signing and as whether a self-hosted instance can serve as an
adopter's own channel.

### Commit signing, set up in the same session

The last branch protection control the design record was waiting on. SSH signing with the
maintainer's existing key, configured globally: signing format, signing key, commit and tag
signing, and an allowed signers file. That last one is why local verification had been
erroring rather than reporting anything useful.

The key needed registering on GitHub a second time, as a signing key rather than an
authentication key, which needs a scope the existing token did not carry and took an
interactive re-authorisation. A commit pushed to a throwaway branch came back verified,
which also proved the committer address is a verified email on the account. Required
signatures are now on for `fleet-main` in all three repositories.

Two things worth keeping. GitHub signs its own merge commits, so enforcement does not fight
the merge button. Those merge commits show locally as unverifiable rather than good, because
the allowed signers file lists one key and GitHub's key is not in it, and GitHub's own view
is the authority there.

### Hazards met along the way

None of these is written down anywhere and each cost time.

A bare `gh pr create` aims at upstream. It takes a fork's parent as the default base, so the
first pull request of the session was opened against `omacom/omarchy` and failed only
because there were no commits between the two. The same command from a branch that shared
history with upstream would have opened a pull request on someone else's repository. Now
recorded in all three `AGENTS.md` files.

`gum input` crashes under an SSH pseudo-terminal, so the factory reset's typed confirmation
cannot be driven over SSH at all. Drive it in the machine's own terminal.

Hyprland takes dispatch arguments as Lua on current builds, so the documented string form of
`movetoworkspacesilent` with a window address is a syntax error, and the Lua dispatcher table
has no by-address form.

`virsh undefine --remove-all-storage` removes the read-only installer ISO and the autoinstall
drive as well as the machine's own disk. When two machines share one ISO, tearing the first
one down deletes the ISO the rebuild is about to boot from.

A viewer window resizes the guest display to fit itself, so a small window gives a small
screen and menus overflow it.
