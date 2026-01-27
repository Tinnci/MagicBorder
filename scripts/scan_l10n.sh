#!/bin/bash

# Find potential hardcoded strings
echo "Scanning for hardcoded strings in Sources/MagicBorder/UI..."
grep -rE "Text\(\"[^\"]+\"\)|Label\(\"[^\"]+\",|Button\(\"[^\"]+\"" Sources/MagicBorder/UI | grep -v "localized:" | grep -v "verbatim:"
