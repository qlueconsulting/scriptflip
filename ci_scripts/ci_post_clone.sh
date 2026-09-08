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
# Set BUILD_NUMBER in your Xcode Cloud workflow env vars.
# Use "auto" (or any non-numeric value) to let Xcode Cloud auto-increment.
# Use a specific integer (e.g. "1") to pin the build number for that run.
if [ "$BUILD_NUMBER" = "auto" ] || [ -z "$BUILD_NUMBER" ]; then
  RESOLVED_BUILD_NUMBER="$CI_BUILD_NUMBER"
  echo "-> BUILD_NUMBER=auto, using CI_BUILD_NUMBER = $CI_BUILD_NUMBER"
else
  RESOLVED_BUILD_NUMBER="$BUILD_NUMBER"
  echo "-> BUILD_NUMBER overridden to $BUILD_NUMBER"
fi

if [ -n "$RESOLVED_BUILD_NUMBER" ]; then
  sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9][0-9]*/CURRENT_PROJECT_VERSION = ${RESOLVED_BUILD_NUMBER}/g" ScriptFlip.xcodeproj/project.pbxproj
  echo "   Done. CURRENT_PROJECT_VERSION = $RESOLVED_BUILD_NUMBER"
fi

echo "=== Post-Clone Complete ==="