#!/usr/bin/env bash
# install.sh — register the Trail of Bits and Cloudflare plugin marketplaces in omp
# from GitHub, and install the plugins that audit.sh uses, at user scope.
#
# Both marketplaces use the same mechanism (omp plugin marketplace + omp plugin
# install), so `omp plugin upgrade` updates them the same way.
# Safe to re-run: an existing marketplace or plugin is reported and skipped.
set -euo pipefail

command -v omp >/dev/null || { echo "install.sh: omp is not on PATH" >&2; exit 1; }

marketplaces=(trailofbits/skills cloudflare/skills)

tob_plugins=(
  audit-context-building
  building-secure-contracts
  differential-review
  dimensional-analysis
  entry-point-analyzer
  fp-check
  insecure-defaults
  property-based-testing
  spec-to-code-compliance
  static-analysis
  supply-chain-risk-auditor
  trailmark
  variant-analysis
)

configured=$(omp plugin marketplace list)
for m in "${marketplaces[@]}"; do
  if grep -qF " $m" <<<"$configured"; then
    echo "marketplace $m: already configured"
  else
    omp plugin marketplace add "$m"
  fi
done
omp plugin marketplace update

installed=$(omp plugin list)
install() {
  if grep -qF "$1 (" <<<"$installed"; then
    echo "plugin $1: already installed"
  else
    omp plugin install "$1" --scope user
  fi
}
for p in "${tob_plugins[@]}"; do install "$p@trailofbits"; done
install cloudflare@cloudflare

omp plugin doctor

# CLIs that the static-analysis and trailmark skills call. uv installs each into its own
# tool environment; `uv tool install` of a present tool is a no-op.
command -v uv >/dev/null || { echo "install.sh: uv is not on PATH (https://docs.astral.sh/uv/)" >&2; exit 1; }
uv tool install semgrep
uv tool install trailmark
