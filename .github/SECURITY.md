# Security

This repository is a fork of [omacom/omarchy](https://github.com/omacom/omarchy) carrying the Omarchy Fleet work. It is not Omarchy, and reports about it do not reach Omarchy's maintainers.

## Report a vulnerability in the fleet code

Use this repository's Security tab and choose "Report a vulnerability", which opens a private advisory that only the maintainers of this fork can read. Please do not open a public issue for something exploitable.

The fleet code is the part that is specific to this fork: `bin/omarchy-fleet*`, `bin/omarchy-profile-fleet`, `install/helpers/fleet.sh`, `install/config/fleet.sh`, and their tests and plans.

## Report a vulnerability in Omarchy itself

Everything else here is upstream's code. Report it to the [Omarchy Security Team](https://omarchy.org/teams/#security) at [security@omarchy.org](mailto:security@omarchy.org?subject=Security%20report), so the fix reaches every Omarchy user rather than only this fork.

## What this fork does not do yet

No fleet configuration is fetched, verified or applied by any released code here. A machine can record where its configuration will come from and nothing reads that record. Signature verification is the trust boundary once it exists, and until then nothing in this repository acts on a remote source.
