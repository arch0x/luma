#!/bin/sh
# List documents in the current directory without modifying them.
for document in ./*.md; do
  [ -f "$document" ] || continue
  printf 'Continue reading: %s\n' "$document"
done
