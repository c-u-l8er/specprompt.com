#!/bin/sh
# ==========================================================================
# specprompt.com — regenerate the landing page and re-prove it.
#
#     ./site.sh
#
# There is deliberately no package.json at the root of this repository: it is
# an Elixir project, `mix.exs` is where the version lives, and adding a second
# manifest so the shell's usual release-identity check has something familiar
# to read would be inventing the evidence rather than finding it.
#
# The build RUNS the suites and refuses if a count has moved off the frozen
# record; the gate then reads the emitted artifact and refuses if the artifact
# and the records disagree. Point any hosted build command at THIS script,
# never at the build alone — a plain build deploys an unproven artifact.
# ==========================================================================
set -e
cd "$(dirname "$0")"
node build-site.mjs
node launch-gate.mjs
