#!/bin/bash

# Run the app with localization debugging flags
# -NSShowNonLocalizedStrings YES: Logs strings that are not found in the string catalog
# -AppleLanguages (de): Helper to launch in a specific language (e.g. German) to test layout

LANGUAGE=${1:-"en"}
echo "Launching MagicBorder with localization debugging..."
echo "Language: $LANGUAGE"
echo "Check console for Uppercase strings (missing translations)"

swift run MagicBorder -NSShowNonLocalizedStrings YES -AppleLanguages "($LANGUAGE)"
