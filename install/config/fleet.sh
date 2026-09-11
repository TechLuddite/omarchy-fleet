# A machine installed into a fleet records where its configuration comes from,
# from what the installer put in the environment. An ISO built for a fleet sets
# OMARCHY_FLEET_CONFIG_URL; every other install sets nothing and this leaf does
# nothing at all.
#
# Only the record is written here. Nothing is fetched, verified or applied, so
# an install that cannot reach the configuration repository still finishes.
if [[ -n ${OMARCHY_FLEET_CONFIG_URL:-} ]]; then
  fleet_enroll_args=(--config-url "$OMARCHY_FLEET_CONFIG_URL")

  # Passed only when set, since an empty value is refused rather than treated
  # as absent, and the command has its own defaults for the rest.
  [[ -z ${OMARCHY_FLEET_SIGNING_KEY:-} ]] || fleet_enroll_args+=(--signing-key "$OMARCHY_FLEET_SIGNING_KEY")
  [[ -z ${OMARCHY_FLEET_HOST_ID:-} ]] || fleet_enroll_args+=(--host-id "$OMARCHY_FLEET_HOST_ID")
  [[ -z ${OMARCHY_FLEET_ROLES:-} ]] || fleet_enroll_args+=(--roles "$OMARCHY_FLEET_ROLES")
  [[ -z ${OMARCHY_FLEET_USER_CONFIG:-} ]] || fleet_enroll_args+=(--user-config "$OMARCHY_FLEET_USER_CONFIG")

  omarchy-fleet enroll "${fleet_enroll_args[@]}"
fi
