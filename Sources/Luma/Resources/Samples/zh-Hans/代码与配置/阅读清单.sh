#!/bin/sh
# 只列出当前目录里的文档，不修改文件。
for document in ./*.md; do
  [ -f "$document" ] || continue
  printf '继续阅读：%s\n' "$document"
done
