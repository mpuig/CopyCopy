#!/usr/bin/env fish
# Launch CopyCopy from the binary (avoids permission issues)
set -l SCRIPT_DIR (dirname (status filename))
"$SCRIPT_DIR/dist/CopyCopy.app/Contents/MacOS/CopyCopy" &
