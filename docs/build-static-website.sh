#!/bin/bash

# For some reason the build command tries to use npx, which is not available in the Bun container.
# This script creates a wrapper for npx that uses bunx instead, stripping out the -y arguments.
if command -v bunx >/dev/null 2>&1 && ! command -v npx >/dev/null 2>&1; then
  TARGET="/usr/local/bin/npx"
  cat <<'EOF' > "$TARGET"
#!/bin/sh
# Wrapper for bunx that strips out all -y arguments
args=""
for arg in "$@"; do
  if [ "$arg" != "-y" ]; then
    args="$args \"$arg\""
  fi
done
eval exec bunx $args
EOF
  chmod +x "$TARGET"
  echo "npx wrapper created at $TARGET"
else
  echo "Not a Bun container (bunx not found or npx already exists). Skipping wrapper."
fi


cd ./docs/src || exit
bun install
bun run build
