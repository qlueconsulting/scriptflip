#!/bin/sh
set -e

echo "=== Xcode Cloud Post-Clone Hook ==="
echo "CI_BUILD_NUMBER:    ${CI_BUILD_NUMBER:-not set}"
echo "CI_WORKFLOW:        ${CI_WORKFLOW:-not set}"
echo "MARKETING_VERSION:  ${MARKETING_VERSION:-not set (using project default)}"
echo "BUILD_NUMBER:       ${BUILD_NUMBER:-not set (using CI_BUILD_NUMBER)}"

# ── Marketing Version ────────────────────────────────────────────────────────
# Set MARKETING_VERSION as an env var in your Xcode Cloud workflow to override.
# Example: MARKETING_VERSION = 1.0.1
if [ -n "$MARKETING_VERSION" ]; then
  echo "-> Applying MARKETING_VERSION = $MARKETING_VERSION"
  sed -i '' "s/MARKETING_VERSION = [0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/MARKETING_VERSION = ${MARKETING_VERSION}/g" ScriptFlip.xcodeproj/project.pbxproj
  echo "   Done. MARKETING_VERSION = $MARKETING_VERSION"
else
  echo "-> MARKETING_VERSION not overridden - using value from project.pbxproj"
fi

# ── Build Number ─────────────────────────────────────────────────────────────
# Set BUILD_NUMBER as an env var in your Xcode Cloud workflow to pin a number.
# Falls back to Xcode Cloud's auto-incrementing CI_BUILD_NUMBER if not set.
RESOLVED_BUILD_NUMBER="${BUILD_NUMBER:-$CI_BUILD_NUMBER}"
if [ -n "$RESOLVED_BUILD_NUMBER" ]; then
  echo "-> Applying CURRENT_PROJECT_VERSION = $RESOLVED_BUILD_NUMBER"
  sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9][0-9]*/CURRENT_PROJECT_VERSION = ${RESOLVED_BUILD_NUMBER}/g" ScriptFlip.xcodeproj/project.pbxproj
  echo "   Done. CURRENT_PROJECT_VERSION = $RESOLVED_BUILD_NUMBER"
else
  echo "-> No build number source found - using value from project.pbxproj"
fi

echo "=== Post-Clone Complete ==="