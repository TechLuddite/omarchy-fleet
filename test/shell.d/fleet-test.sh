#!/bin/bash
#
# The fleet enrolment record and the predicate that reads it. Every case runs
# against a scratch OMARCHY_FLEET_CONF, so nothing here touches /etc.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

conf="$work/etc/omarchy/fleet.conf"
export OMARCHY_FLEET_CONF="$conf"
export OMARCHY_PATH="$ROOT"

# A fresh record for each case, so one case cannot leave state another reads.
reset_conf() {
  rm -rf "$work/etc"
}

helper() {
  OMARCHY_FLEET_CONF="$conf" bash -c '
    source "$1"
    shift
    "$@"
  ' _ "$ROOT/install/helpers/fleet.sh" "$@"
}

predicate() {
  OMARCHY_FLEET_CONF="$conf" OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-profile-fleet"
}

# The predicate is what every menu guard and later provider asks, so what it
# calls enrolled is the definition of enrolled.

reset_conf
predicate && fail "no record means not enrolled"
pass "a machine with no record is not enrolled"

reset_conf
helper fleet_conf_set config_url "https://github.com/example/fleet-config.git" ||
  fail "the record can be written"
predicate || fail "a record naming a config_url means enrolled"
pass "a record naming a config_url means enrolled"

reset_conf
helper fleet_conf_set config_url "" || fail "an empty value can be written"
predicate && fail "an empty config_url does not mean enrolled"
pass "a record with an empty config_url is not enrolled"

# A git URL is mostly slashes and a fingerprint can be anything, so a writer
# that fed the value to sed would mangle both. This is the case that would
# catch that.

reset_conf
helper fleet_conf_set config_url "git@github.com:example/fleet-config.git"
helper fleet_conf_set config_url "https://git.example.org/a/b/c.git?ref=main&x=1"
[[ $(helper fleet_conf_get config_url) == "https://git.example.org/a/b/c.git?ref=main&x=1" ]] ||
  fail "a rewritten URL survives verbatim" "$(helper fleet_conf_get config_url)"
pass "a value full of slashes and ampersands survives a rewrite verbatim"

reset_conf
helper fleet_conf_set config_url "https://example.org/one.git"
helper fleet_conf_set config_url "https://example.org/two.git"
(( $(grep -c '^config_url=' "$conf") == 1 )) ||
  fail "rewriting a key leaves one line" "$(cat "$conf")"
pass "rewriting a key leaves exactly one line for it"

reset_conf
helper fleet_conf_set config_url "https://example.org/one.git"
helper fleet_conf_set host_id "till-01"
helper fleet_conf_set roles "kiosk backup-target"
[[ $(helper fleet_conf_get host_id) == "till-01" ]] || fail "each key reads back"
[[ $(helper fleet_conf_get roles) == "kiosk backup-target" ]] || fail "roles read back"
[[ $(helper fleet_conf_get config_url) == "https://example.org/one.git" ]] ||
  fail "setting one key leaves the others alone"
pass "keys are written and read independently"

reset_conf
helper fleet_conf_set config_url "https://example.org/one.git"
[[ $(helper fleet_conf_get user_config delegated) == "delegated" ]] ||
  fail "an absent key falls back to its default"
pass "an absent key falls back to its default"

# The record is world-readable on purpose: everything in it is a fact about
# this machine that any of its users can already discover.

reset_conf
helper fleet_conf_set config_url "https://example.org/one.git"
[[ $(stat -c '%a' "$conf") == "644" ]] || fail "the record is mode 644" "$(stat -c '%a' "$conf")"
pass "the record is written world-readable"

reset_conf
helper fleet_conf_set config_url "https://example.org/one.git"
grep -q '^# Omarchy fleet enrolment' "$conf" || fail "a new record explains itself"
grep -q 'Nothing here is secret' "$conf" || fail "a new record says what it does not hold"
pass "a new record carries its own explanation"

# document writes a default the first time and never argues with a choice
# somebody has already made.

reset_conf
helper fleet_conf_document user_config delegated "How much of the user's config Fleet owns."
[[ $(helper fleet_conf_get user_config) == "delegated" ]] || fail "document writes its default"
grep -q "^# How much of the user's config Fleet owns.$" "$conf" ||
  fail "document writes its comment" "$(cat "$conf")"
helper fleet_conf_set user_config managed
helper fleet_conf_document user_config delegated "How much of the user's config Fleet owns."
[[ $(helper fleet_conf_get user_config) == "managed" ]] ||
  fail "document leaves an explicit value alone" "$(helper fleet_conf_get user_config)"
pass "a documented default never overwrites an explicit value"

# The concurrency case the kids mode helper grew its lock for: an explicit
# choice and a documented default racing on a record that does not exist yet.

reset_conf
for _ in 1 2 3 4 5 6 7 8; do
  helper fleet_conf_set user_config managed &
  helper fleet_conf_document user_config delegated "How much of the user's config Fleet owns." &
  wait
  [[ $(helper fleet_conf_get user_config) == "managed" ]] ||
    fail "an explicit value survives a concurrent documented default" "$(cat "$conf")"
  (( $(grep -c '^user_config=' "$conf") == 1 )) ||
    fail "a concurrent write leaves one line for the key" "$(cat "$conf")"
  reset_conf
done
pass "an explicit value survives a documented default racing it"

# Nothing may write a key that is not an identifier or a value carrying a
# newline: the first is interpolated into a regex, and the second would land as
# a line that parses as something else.

reset_conf
helper fleet_conf_set 'config_url; rm -rf /' x && fail "a key that is not an identifier is refused"
helper fleet_conf_set config_url $'https://example.org/one.git\nroles=admin' &&
  fail "a value carrying a newline is refused"
[[ ! -f $conf ]] || fail "a refused write creates nothing" "$(cat "$conf")"
pass "a bad key or a value carrying a newline is refused before anything is written"

reset_conf
helper fleet_conf_set config_url "https://example.org/one.git"
helper fleet_conf_remove
[[ ! -f $conf ]] || fail "the record can be removed"
predicate && fail "a removed record means not enrolled"
helper fleet_conf_remove || fail "removing a record that is already gone is not an error"
pass "the record can be removed, and removing it twice is not an error"

# --- the command -------------------------------------------------------------

export PATH="$ROOT/bin:$PATH"

fleet() {
  OMARCHY_FLEET_CONF="$conf" OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-fleet" "$@"
}

# enroll and leave write under /etc, so they check for root and otherwise
# re-exec under sudo. Reach them as namespaced root, the way dns-sudoers-test
# does, and skip where a sandbox or a hardened kernel refuses user namespaces:
# a skip is a passing test on a machine that cannot run it.
root_runner=()
can_be_root=0
if (( EUID == 0 )); then
  can_be_root=1
elif unshare --user --map-root-user true 2>/dev/null; then
  root_runner=(unshare --user --map-root-user)
  can_be_root=1
fi

root_fleet() {
  "${root_runner[@]}" env OMARCHY_FLEET_CONF="$conf" OMARCHY_PATH="$ROOT" \
    "$ROOT/bin/omarchy-fleet" "$@"
}

reset_conf
fleet --help >/dev/null || fail "--help exits cleanly"
fleet >/dev/null 2>&1 && fail "no subcommand is an error"
fleet nonsense >/dev/null 2>&1 && fail "an unknown subcommand is an error"
pass "help, no subcommand, and an unknown subcommand each answer correctly"

reset_conf
status=$(fleet status) || fail "status on an unenrolled machine exits 0"
[[ $status == *"Enrolled     no"* ]] || fail "status says it is not enrolled" "$status"
[[ $status == *"omarchy fleet enroll"* ]] || fail "status says how to enrol" "$status"
[[ ! -f $conf ]] || fail "status writes nothing"
pass "status on an unenrolled machine reports and writes nothing"

if (( can_be_root == 0 )); then
  pass "no way to reach root; skipping the enroll and leave cases"
  exit 0
fi

# A first enrolment must name both, because a machine enrolled without a
# signing key would need an exception the day verification becomes the default.

reset_conf
root_fleet enroll --signing-key ABCD1234 >/dev/null 2>&1 &&
  fail "enrolling without a config URL is refused"
root_fleet enroll --config-url https://example.org/fleet.git >/dev/null 2>&1 &&
  fail "enrolling without a signing key is refused"
[[ ! -f $conf ]] || fail "a refused enrolment writes nothing" "$(cat "$conf")"
pass "a first enrolment needs both a config URL and a signing key"

reset_conf
for bad in "not a url" "ftp://example.org/x.git" "https://example.org"; do
  root_fleet enroll --config-url "$bad" --signing-key ABCD1234 >/dev/null 2>&1 &&
    fail "a config URL that is not a git URL is refused: $bad"
done
root_fleet enroll --config-url https://example.org/fleet.git --signing-key 'bad key!' >/dev/null 2>&1 &&
  fail "a signing key that is not a fingerprint is refused"
root_fleet enroll --config-url https://example.org/fleet.git --signing-key ABCD1234 \
  --user-config sometimes >/dev/null 2>&1 && fail "an unknown user config mode is refused"
root_fleet enroll --config-url https://example.org/fleet.git --signing-key ABCD1234 \
  --roles "kiosk bad/role" >/dev/null 2>&1 && fail "a role that is not a word is refused"
root_fleet enroll --config-url https://example.org/fleet.git --signing-key ABCD1234 \
  --host-id "till 1" >/dev/null 2>&1 && fail "a host id with a space is refused"
[[ ! -f $conf ]] || fail "no rejected value leaves a half-written record" "$(cat "$conf")"
pass "every value is checked before anything is written"

reset_conf
root_fleet enroll --config-url "git@github.com:example/fleet.git" --signing-key ABCD1234 >/dev/null ||
  fail "an scp-form git URL enrols"
[[ $(helper fleet_conf_get config_url) == "git@github.com:example/fleet.git" ]] ||
  fail "the scp-form URL is recorded verbatim"
pass "an scp-form git URL is accepted and recorded verbatim"

reset_conf
root_fleet enroll --config-url https://example.org/fleet.git --signing-key ABCD1234 >/dev/null ||
  fail "a valid enrolment succeeds"
predicate || fail "an enrolled machine answers the predicate"
[[ $(helper fleet_conf_get host_id) == "$(uname -n)" ]] ||
  fail "host id defaults to the hostname and is pinned" "$(helper fleet_conf_get host_id)"
[[ $(helper fleet_conf_get user_config) == "delegated" ]] ||
  fail "user config defaults to delegated" "$(helper fleet_conf_get user_config)"
pass "enrolling records the values and pins the defaults"

status=$(fleet status)
[[ $status == *"Enrolled     yes"* ]] || fail "status reports enrolled" "$status"
[[ $status == *"https://example.org/fleet.git"* ]] || fail "status shows the config URL" "$status"
[[ $status == *"Nothing has been fetched, verified or applied"* ]] ||
  fail "status says nothing has been applied" "$status"
pass "status reports the record and says nothing has been applied"

changes=$(root_fleet enroll --config-url https://example.org/fleet.git --signing-key ABCD1234)
[[ $changes != *"config_url="* ]] || fail "a repeated enrolment reports no change" "$changes"
pass "enrolling twice with the same values changes nothing"

changes=$(root_fleet enroll --roles "kiosk backup-target")
[[ $changes == *"roles=kiosk backup-target"* ]] || fail "a later enrolment can set roles" "$changes"
[[ $(helper fleet_conf_get config_url) == "https://example.org/fleet.git" ]] ||
  fail "a later enrolment leaves the other values alone"
[[ $(helper fleet_conf_get user_config) == "delegated" ]] ||
  fail "a later enrolment leaves the defaults alone"
pass "a later enrolment changes only what it is given"

changes=$(root_fleet enroll --user-config managed)
[[ $changes == *"user_config=managed"* ]] || fail "the user config mode can be changed" "$changes"
[[ $(helper fleet_conf_get roles) == "kiosk backup-target" ]] ||
  fail "changing one key leaves the last one alone"
pass "the recorded user config mode can be changed"

left=$(root_fleet leave)
[[ $left == *"no longer records"* ]] || fail "leave says what it removed" "$left"
[[ ! -f $conf ]] || fail "leave removes the record"
predicate && fail "a machine that left is not enrolled"
left=$(root_fleet leave)
[[ $left == *"nothing to remove"* ]] || fail "leaving twice is not an error" "$left"
pass "leave removes the record, and leaving twice is not an error"

# A feature or provider plugs in as a binary on the path, never as an edit to
# the command that dispatches to it.
reset_conf
mkdir -p "$work/bin"
cat >"$work/bin/omarchy-fleet-demo" <<'DEMO'
#!/bin/bash
# omarchy:summary=A stand-in feature command
echo "demo ran with: $*"
DEMO
chmod +x "$work/bin/omarchy-fleet-demo"
dispatched=$(PATH="$work/bin:$PATH" fleet demo one two)
[[ $dispatched == "demo ran with: one two" ]] ||
  fail "an unknown subcommand reaches its feature command" "$dispatched"
pass "a feature command is reached by adding a binary, not by editing the dispatcher"

# --- the install leaf --------------------------------------------------------

# The leaf is sourced during installation, so it is exercised the same way,
# against a stub command that records what it was asked to do.
leaf() {
  local log="$work/enroll.log"
  rm -f "$log"
  mkdir -p "$work/stub"
  cat >"$work/stub/omarchy-fleet" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >"$log"
STUB
  chmod +x "$work/stub/omarchy-fleet"
  (
    export PATH="$work/stub:$PATH"
    # shellcheck source=/dev/null
    source "$ROOT/install/config/fleet.sh"
  )
  cat "$log" 2>/dev/null || true
}

reset_conf
called=$(env -u OMARCHY_FLEET_CONFIG_URL bash -c "$(declare -f leaf); work=$work; ROOT=$ROOT; leaf")
[[ -z $called ]] || fail "the leaf does nothing when the installer set no fleet" "$called"
pass "the install leaf does nothing on a machine installed outside a fleet"

called=$(
  OMARCHY_FLEET_CONFIG_URL=https://example.org/fleet.git \
  OMARCHY_FLEET_SIGNING_KEY=ABCD1234 \
    bash -c "$(declare -f leaf); work=$work; ROOT=$ROOT; leaf"
)
[[ $called == "enroll --config-url https://example.org/fleet.git --signing-key ABCD1234" ]] ||
  fail "the leaf enrols from the installer's environment" "$called"
pass "the install leaf enrols from what the installer recorded"

called=$(
  OMARCHY_FLEET_CONFIG_URL=https://example.org/fleet.git \
  OMARCHY_FLEET_SIGNING_KEY=ABCD1234 \
  OMARCHY_FLEET_HOST_ID=till-01 \
  OMARCHY_FLEET_ROLES="kiosk backup-target" \
  OMARCHY_FLEET_USER_CONFIG=managed \
    bash -c "$(declare -f leaf); work=$work; ROOT=$ROOT; leaf"
)
[[ $called == "enroll --config-url https://example.org/fleet.git --signing-key ABCD1234 --host-id till-01 --roles kiosk backup-target --user-config managed" ]] ||
  fail "the leaf passes every value the installer set" "$called"
pass "the install leaf passes every value the installer set"
