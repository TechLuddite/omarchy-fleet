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
