# Shared by omarchy-fleet, its feature commands (omarchy-fleet-*), and
# omarchy-profile-fleet, so every one of them reads and writes the enrolment
# record the same way. Sourced with no other requirement on the caller.
#
# Modelled on install/helpers/parent.sh, including the lock it grew after a
# live race between a documented default and an explicit value.

FLEET_CONF="${OMARCHY_FLEET_CONF:-/etc/omarchy/fleet.conf}"

# The enrolment record: one key=value per line, world-readable, every key
# documented in place by the command that owns it (fleet_conf_document), so
# anyone reading the file sees every value and what it is for. It holds facts
# about this machine only: where its configuration comes from, which key signs
# it, what this host is called there, and what it is for. It never holds key
# material, a token, a credential, or anything about another host.
#
# The machine is enrolled exactly when this file exists and names a config_url.
# There is no separate marker, because absence is a complete answer.
#
# All writers share a lock file that survives replacement of the record. Hold
# it from the first existence or key check through the final rename, so
# documenting a default cannot overwrite a concurrent explicit choice. Readers
# take no lock: they see either complete version. The subshell closes the lock
# descriptor and keeps its umask and trap local to this operation.
fleet_conf_change() (
  local operation="$1" key="${2:-}" value="${3:-}" directory lock_fd stage line

  # The key is interpolated into a regex below, and a value carrying a newline
  # would land as a second line that parses as something else entirely.
  if [[ -n $key && ! $key =~ ^[a-z][a-z0-9_]*$ ]]; then
    return 1
  fi
  if [[ $value == *$'\n'* ]]; then
    return 1
  fi

  directory=$(dirname "$FLEET_CONF") || return
  mkdir -p "$directory" || return
  umask 077
  exec {lock_fd}>"$directory/.${FLEET_CONF##*/}.lock" || return
  flock -x "$lock_fd" || return

  if [[ $operation == "init" && -f $FLEET_CONF ]]; then
    return 0
  fi
  if [[ $operation == "document" && -f $FLEET_CONF ]] &&
    grep -q "^[[:space:]]*$key[[:space:]]*=" "$FLEET_CONF"; then
    return 0
  fi

  stage=$(mktemp "$directory/.${FLEET_CONF##*/}.XXXXXX") || return
  trap 'rm -f -- "$stage"' EXIT
  if [[ $operation == "set" && -f $FLEET_CONF ]] &&
    grep -q "^[[:space:]]*$key[[:space:]]*=" "$FLEET_CONF"; then
    # awk rather than sed: a config_url is full of slashes and a fingerprint
    # can carry anything, so the new value must never be read as a replacement
    # expression. The first matching line becomes the new one and any later
    # duplicate is dropped, which leaves one line per key however the file got
    # into that state.
    awk -v key="$key" -v value="$value" '
      $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
        if (!written) {
          print key "=" value
          written = 1
        }
        next
      }
      { print }
    ' "$FLEET_CONF" >"$stage" || return
  else
    if [[ -f $FLEET_CONF ]]; then
      cat "$FLEET_CONF" >"$stage" || return
    else
      cat >"$stage" <<'CONF' || return
# Omarchy fleet enrolment: where this machine's configuration comes from, which
# key signs it, what this host is called there, and what it is for. Each key is
# explained where it appears. Nothing here is secret; every value is a fact
# about this machine that anyone using it can already discover.
#
# Change a value with `sudo omarchy fleet enroll`, which edits this file for
# you and refuses a value it cannot use. A hand edit takes effect at the next
# enroll.
CONF
    fi
    if [[ $operation == "document" ]]; then
      shift 3
      printf '\n' >>"$stage" || return
      for line in "$@"; do printf '# %s\n' "$line" >>"$stage" || return; done
    fi
    if [[ $operation != "init" ]]; then
      printf '%s=%s\n' "$key" "$value" >>"$stage" || return
    fi
  fi
  chmod 644 "$stage" || return
  mv -f -- "$stage" "$FLEET_CONF"
)

fleet_conf_init() {
  fleet_conf_change init
}

# Reads the last assignment of the key, so a hand-edited file with a duplicate
# resolves the way a reader scanning top to bottom would expect. An empty value
# falls back to the default, since a key present with nothing after it says no
# more than an absent one.
fleet_conf_get() {
  local key="$1" default="${2:-}" value=""

  if [[ -f $FLEET_CONF ]]; then
    value=$(sed -n "s/^[[:space:]]*$key[[:space:]]*=[[:space:]]*//p" "$FLEET_CONF" | tail -1)
    value=${value%"${value##*[![:space:]]}"}
  fi

  printf '%s\n' "${value:-$default}"
}

fleet_conf_set() {
  fleet_conf_change set "$@"
}

# fleet_conf_document KEY DEFAULT COMMENT... writes a commented block and the
# default the first time a command sees the file, and leaves a key somebody has
# already set alone.
fleet_conf_document() {
  fleet_conf_change document "$@"
}

# Enrolled exactly when the record exists and names somewhere to get
# configuration from. Every predicate and command asks through this, so none of
# them can disagree about what enrolled means.
fleet_enrolled() {
  [[ -f $FLEET_CONF ]] || return 1
  [[ -n $(fleet_conf_get config_url) ]]
}

fleet_conf_remove() {
  rm -f -- "$FLEET_CONF"
}
