#!/usr/bin/env python3
"""Refresh the checked-in sample catalog, code fixtures and WebP example.

Run generate-assets.swift with --refresh-samples first. This maintenance script
uses Pillow for WebP encoding; ordinary app builds only require Apple tools.
"""
from pathlib import Path
import json
import os
import textwrap

ROOT = Path(__file__).resolve().parent.parent
SAMPLES = ROOT / "Sources/Luma/Resources/Samples"
CATALOG = ROOT / "Sources/Luma/Resources/SampleCatalog.json"
entries = []


def sample(name, extensions, path, section, body=None):
    entries.append(dict(name=name, extensions=extensions.split() if extensions else [], path=path, section=section))
    if body is not None:
        target = SAMPLES / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(textwrap.dedent(body).lstrip("\n").rstrip() + "\n", encoding="utf-8")


sample("Markdown", "md markdown mdown", "欢迎.md", "文档与数据")
sample("PDF", "pdf", "阅读空间.pdf", "文档与数据")
sample("SVG", "svg", "图片资源/阅读 流程.svg", "文档与数据")
sample("JSON", "json", "项目.json", "文档与数据")
sample("GeoJSON", "geojson", "格式示例/阅读位置.geojson", "文档与数据", '''
    {
      "type": "FeatureCollection",
      "features": [{
        "type": "Feature",
        "properties": {"name": "阅读空间", "category": "示例位置"},
        "geometry": {"type": "Point", "coordinates": [120.0, 30.0]}
      }]
    }
''')
sample("JSONC", "jsonc", "格式示例/阅读设置.jsonc", "文档与数据")
sample("JSONL", "jsonl", "格式示例/阅读记录.jsonl", "文档与数据")
sample("NDJSON", "ndjson", "格式示例/文件事件.ndjson", "文档与数据")
sample("CSV", "csv", "阅读清单.csv", "文档与数据")
sample("TSV", "tsv", "格式示例/阅读进度.tsv", "文档与数据", '''
    文档\t状态\t进度\t备注
    欢迎.md\t已阅读\t100\t从这里开始
    图片与公式.md\t阅读中\t50\t图片、公式与表格
    长文档导航.md\t待阅读\t0\t留住当前段落
''')
sample("reStructuredText", "rst", "代码与配置/阅读说明.rst", "文档与数据", '''
    阅读空间
    ========

    这是一份 reStructuredText 源文件，可直接阅读和编辑原文。

    阅读步骤
    --------

    * 找到一份本地资料。
    * 按 ``Command-F`` 查找正文。
    * 写下笔记，保存后继续阅读。
''')

for name, extensions, path in [
    ("PNG", "png", "留白.png"),
    ("JPEG", "jpg jpeg", "图片格式/阅读封面.jpg"),
    ("GIF", "gif", "图片格式/阅读封面.gif"),
    ("HEIC / HEIF", "heic heif", "图片格式/阅读封面.heic"),
    ("TIFF", "tiff tif", "图片格式/阅读封面.tiff"),
    ("BMP", "bmp", "图片格式/阅读封面.bmp"),
    ("WebP", "webp", "图片格式/阅读封面.webp"),
    ("ICNS", "icns", "图片格式/澄览图标.icns"),
]:
    sample(name, extensions, path, "图片")

sample("Dockerfile", "dockerfile", "代码与配置/Dockerfile", "代码", """
    # syntax=docker/dockerfile:1
    # 本地文档预览服务的容器配置，仅供阅读示例。
    ARG PYTHON_VERSION=3.12
    FROM python:${PYTHON_VERSION}-slim AS runtime

    WORKDIR /workspace
    ENV PYTHONUNBUFFERED=1
    COPY . /workspace
    EXPOSE 8000
    CMD ["python", "-m", "http.server", "8000"]
""")
sample(".dockerignore", "dockerignore", "代码与配置/.dockerignore", "文本与配置", """
    # 构建上下文中的排除规则。
    .git/
    .build/
    dist/
    **/*.log
    *.tmp
    !README.md
""")
sample("Swift", "swift", "示例代码.swift", "代码")
code = [
    ("Python", "py", "阅读清单.py", '''
        from pathlib import Path

        def reading_list(folder: Path) -> list[str]:
            """按名称列出 Markdown 文档。"""
            return sorted(path.name for path in folder.glob("*.md"))

        if __name__ == "__main__":
            print(reading_list(Path(".")))
    '''),
    ("JavaScript", "js mjs cjs", "阅读清单.js", '''
        // 一段独立的 JavaScript 模块。
        export const documents = [
          { title: "设计文档", read: true },
          { title: "实验记录", read: false },
        ];

        export function unreadTitles(items = documents) {
          return items.filter(item => !item.read).map(item => item.title);
        }
    '''),
    ("JSX", "jsx", "阅读卡片.jsx", '''
        export default function ReadingCard({ title = "读得清楚", progress = 0 }) {
          return (
            <article className="reading-card">
              <h1>{title}</h1>
              <progress max={100} value={progress} />
              <p>留一点空间，给专注。</p>
            </article>
          );
        }
    '''),
    ("TypeScript", "ts mts cts", "阅读清单.ts", '''
        interface ReadingItem {
          title: string;
          progress: number;
        }

        export const documents: ReadingItem[] = [
          { title: "设计文档", progress: 1 },
          { title: "实验记录", progress: 0.5 },
        ];

        export const unfinished = documents.filter(item => item.progress < 1);
    '''),
    ("TSX", "tsx", "阅读卡片.tsx", '''
        type Props = { title: string; progress?: number };

        export default function ReadingCard({ title, progress = 0 }: Props) {
          return (
            <article className="reading-card">
              <h1>{title}</h1>
              <progress max={100} value={progress} />
            </article>
          );
        }
    '''),
    ("Rust", "rs", "阅读清单.rs", '''
        struct Document<'a> {
            title: &'a str,
            read: bool,
        }

        fn main() {
            let document = Document { title: "读得清楚", read: false };
            if !document.read {
                println!("继续阅读：{}", document.title);
            }
        }
    '''),
    ("Go", "go", "阅读清单.go", '''
        package main

        import "fmt"

        type Document struct {
            Title string
            Read  bool
        }

        func main() {
            note := Document{Title: "读得清楚", Read: false}
            fmt.Println(note.Title)
        }
    '''),
    ("Ruby", "rb", "阅读清单.rb", '''
        Document = Struct.new(:title, :read, keyword_init: true)
        documents = [
          Document.new(title: "设计文档", read: true),
          Document.new(title: "实验记录", read: false)
        ]

        documents.reject(&:read).each { |item| puts "继续阅读：#{item.title}" }
    '''),
    ("C", "c h", "阅读清单.c", '''
        #include <stdbool.h>
        #include <stdio.h>

        struct Document {
            const char *title;
            bool read;
        };

        int main(void) {
            struct Document note = {"Luma", false};
            printf("Continue reading: %s\\n", note.title);
            return 0;
        }
    '''),
    ("C++", "cpp hpp cc cxx hh hxx", "阅读清单.cpp", '''
        #include <iostream>
        #include <string>
        #include <vector>

        int main() {
            const std::vector<std::string> titles{"设计文档", "实验记录"};
            for (const auto& title : titles) {
                std::cout << title << '\\n';
            }
        }
    '''),
    ("C#", "cs", "阅读清单.cs", '''
        using System;
        using System.Linq;

        public record Document(string Title, bool Read);

        public static class Program {
            public static void Main() {
                var notes = new[] { new Document("读得清楚", false) };
                foreach (var note in notes.Where(item => !item.Read))
                    Console.WriteLine(note.Title);
            }
        }
    '''),
    ("Objective-C", "m mm", "阅读清单.m", '''
        #import <Foundation/Foundation.h>

        int main(int argc, const char *argv[]) {
            @autoreleasepool {
                NSArray<NSString *> *titles = @[@"设计文档", @"实验记录"];
                for (NSString *title in titles) {
                    NSLog(@"继续阅读：%@", title);
                }
            }
            return 0;
        }
    '''),
    ("Java", "java", "ReadingList.java", '''
        import java.util.List;

        public class ReadingList {
            record Document(String title, boolean read) {}

            public static void main(String[] args) {
                var notes = List.of(new Document("读得清楚", false));
                notes.stream().filter(note -> !note.read())
                    .forEach(note -> System.out.println(note.title()));
            }
        }
    '''),
    ("Kotlin", "kt kts", "阅读清单.kt", '''
        data class Document(val title: String, val read: Boolean = false)

        fun main() {
            val notes = listOf(Document("设计文档", true), Document("实验记录"))
            notes.filterNot { it.read }.forEach { println(it.title) }
        }
    '''),
    ("Shell", "sh bash zsh bashrc zshrc", "阅读清单.sh", '''
        #!/bin/sh
        # 只列出当前目录里的文档，不修改文件。
        for document in ./*.md; do
          [ -f "$document" ] || continue
          printf '继续阅读：%s\\n' "$document"
        done
    '''),
    ("Fish", "fish", "阅读清单.fish", '''
        # Fish shell：列出本地文档。
        function reading_list
            for document in *.md
                printf '继续阅读：%s\\n' "$document"
            end
        end
    '''),
    ("PHP", "php", "阅读清单.php", '''
        <?php
        declare(strict_types=1);

        $documents = [
            ['title' => '设计文档', 'read' => true],
            ['title' => '实验记录', 'read' => false],
        ];

        foreach ($documents as $document) {
            if (!$document['read']) {
                echo $document['title'] . PHP_EOL;
            }
        }
    '''),
    ("Lua", "lua", "阅读清单.lua", '''
        local documents = {
          { title = "设计文档", read = true },
          { title = "实验记录", read = false },
        }

        for _, document in ipairs(documents) do
          if not document.read then
            print("继续阅读：" .. document.title)
          end
        end
    '''),
    ("Perl", "pl", "阅读清单.pl", '''
        use strict;
        use warnings;
        use utf8;
        binmode STDOUT, ':encoding(UTF-8)';

        my @titles = ('设计文档', '实验记录');
        for my $title (@titles) {
            print "继续阅读：$title\\n";
        }
    '''),
    ("R", "r", "阅读进度.r", '''
        documents <- data.frame(
          title = c("设计文档", "实验记录", "代码片段"),
          progress = c(1.0, 0.5, 0.0)
        )

        unfinished <- subset(documents, progress < 1)
        print(unfinished)
    '''),
    ("SQL", "sql", "阅读清单.sql", '''
        -- 这是一份供阅读的 SQL 源文件，打开时不会执行。
        CREATE TABLE documents (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            progress REAL DEFAULT 0
        );

        INSERT INTO documents (title, progress) VALUES ('设计文档', 0.5);
        SELECT title FROM documents WHERE progress < 1 ORDER BY title;
    '''),
    ("GraphQL", "graphql gql", "阅读清单.graphql", '''
        query ReadingList($limit: Int = 10) {
          documents(limit: $limit, status: READING) {
            id
            title
            progress
          }
        }
    '''),
    ("Makefile", "mk", "Makefile", 'SAMPLES := ..\n\n.PHONY: list\nlist:\n\t@printf "本地阅读空间\\n"\n\t@find "$(SAMPLES)" -name "*.md" -type f\n'),
    ("HTML", "html htm xhtml", "阅读卡片.html", '''
        <!doctype html>
        <html lang="zh-CN">
          <head><meta charset="utf-8"><title>读得清楚</title></head>
          <body>
            <article class="reading-card">
              <h1>读得清楚</h1>
              <p>留一点空间，给专注。</p>
            </article>
          </body>
        </html>
    '''),
    ("CSS", "css", "阅读卡片.css", '''
        :root {
          --accent: #3a6095;
          --paper: #fcfcfa;
          --ink: #1a202b;
        }

        .reading-card {
          max-width: 52rem;
          margin-inline: auto;
          padding: 2rem;
          color: var(--ink);
          background: var(--paper);
          border-left: 3px solid var(--accent);
        }
    '''),
    ("SCSS", "scss", "阅读卡片.scss", '''
        $accent: #3a6095;
        $paper: #fcfcfa;
        $ink: #1a202b;

        .reading-card {
          padding: 2rem;
          color: $ink;
          background: $paper;

          &__title { color: $accent; }
        }
    '''),
]
for name, extensions, filename, body in code:
    sample(name, extensions, "代码与配置/" + filename, "代码", body)
sample("Vue", "vue", "格式示例/阅读卡片.vue", "代码")
sample("Svelte", "svelte", "格式示例/阅读卡片.svelte", "代码")
sample("Less", "less", "格式示例/阅读卡片.less", "代码")
sample("Diff / Patch", "diff patch", "格式示例/排版调整.diff", "代码", '''
    diff --git a/reading-card.css b/reading-card.css
    --- a/reading-card.css
    +++ b/reading-card.css
    @@ -1,5 +1,5 @@
     .reading-card {
    -  max-width: 40rem;
    -  padding: 1rem;
    +  max-width: 52rem;
    +  padding: 2rem;
       color: #1a202b;
     }
''')

config = [
    ("YAML", "yaml yml", "阅读设置.yaml", '''
        workspace: 我的本地阅读空间
        appearance: system
        reading:
          fontSize: 15
          lineHeight: 1.85
        collections:
          - 设计文档
          - 实验记录
    '''),
    ("TOML", "toml", "阅读设置.toml", '''
        workspace = "我的本地阅读空间"
        appearance = "system"

        [reading]
        font_size = 15
        line_height = 1.85
        max_width = 840
    '''),
    ("XML", "xml", "阅读清单.xml", '''
        <?xml version="1.0" encoding="UTF-8"?>
        <reading-list title="我的本地阅读空间">
          <document format="markdown" progress="0.5">设计文档.md</document>
          <document format="pdf" progress="1">阅读空间.pdf</document>
        </reading-list>
    '''),
    ("Property List", "plist", "阅读设置.plist", '''
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
          <dict>
            <key>workspace</key><string>我的本地阅读空间</string>
            <key>fontSize</key><integer>15</integer>
            <key>rememberPosition</key><true/>
          </dict>
        </plist>
    '''),
    ("INI", "ini", "阅读设置.ini", '''
        [workspace]
        name = Luma
        appearance = system

        [reading]
        font_size = 15
        max_width = 840
    '''),
    ("Properties", "properties", "阅读设置.properties", '''
        # 应用设置的键值文本示例。
        workspace.name=Luma
        appearance=system
        reading.fontSize=15
        reading.maxWidth=840
    '''),
    ("Conf / Config", "conf config", "阅读服务.conf", '''
        # 通用配置文本，不会启动服务。
        workspace "我的本地阅读空间" {
            appearance system;
            remember_position true;
            reading_width 840;
        }
    '''),
    ("Environment", "env", ".env", '''
        # 仅使用公开示例值，不包含密码或令牌。
        export WORKSPACE_NAME=Luma
        APPEARANCE=system
        READING_WIDTH=840
        BASE_PATH=./documents
        INDEX_PATH="${BASE_PATH}/index.md"
        WELCOME_MESSAGE="你好 # 这是值的一部分"
    '''),
    ("Git Ignore", "gitignore", ".gitignore", '''
        # 工作区临时文件与否定规则。
        .DS_Store
        .build/
        dist/
        **/*.log
        *.tmp
        !README.md
        !阅读记录.log
        cache?/
        \\#literal-name
    '''),
    ("EditorConfig", "editorconfig", ".editorconfig", '''
        root = true

        [*]
        charset = utf-8
        end_of_line = lf
        insert_final_newline = true
        indent_style = space
        indent_size = 2
    '''),
    ("Xcode Configuration", "xcconfig", "阅读设置.xcconfig", '''
        // Xcode 构建设置文本示例。
        PRODUCT_NAME = Luma
        MACOSX_DEPLOYMENT_TARGET = 14.0
        SWIFT_VERSION = 6.0
        SWIFT_STRICT_CONCURRENCY = complete
    '''),
    ("Lock File", "lock", "Cargo.lock", '''
        # 依赖锁定文本示例。
        version = 4

        [[package]]
        name = "reading-notes"
        version = "1.0.0"
    '''),
    ("Log", "log", "阅读记录.log", '''
        2026-11-09T09:00:00+08:00 INFO opened document=欢迎.md
        2026-11-09T09:01:00+08:00 INFO preview format=SVG source=local
        2026-11-09T09:02:00+08:00 INFO saved document=阅读笔记.txt
    '''),
    ("Plain Text", "txt", "阅读笔记.txt", '''
        我的本地阅读空间

        今天想读：
        - 一份设计文档
        - 一组实验记录
        - 一段刚写好的代码

        按 Command-F 查找，写下笔记后用 Command-S 保存。
    '''),
]
for name, extensions, filename, body in config:
    sample(name, extensions, "代码与配置/" + filename, "文本与配置", body)
sample("自定义扩展名文本", "", "格式示例/工作区.luma-note", "文本与配置")

# Same-format duplicates are consolidated; image encodings and distinct languages remain separate.
for obsolete in ["代码与配置/阅读任务.mk", "格式示例/阅读卡片.svg", "格式示例/设置调整.patch", "格式示例/配色调整.diff"]:
    (SAMPLES / obsolete).unlink(missing_ok=True)

CATALOG.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

intro = '''# 文件格式导览

这是 **2026.11 蓝色主题示例集**。每种格式或语言保留一份代表文件；同格式的别名扩展名合并展示。

## 从这里体验

- [独立 SVG](<../图片资源/阅读 流程.svg>)：缩放、适合窗口、源码与图形切换。
- [JSONC](阅读设置.jsonc)：格式化保留注释和尾逗号。
- [JSONL](阅读记录.jsonl) / [NDJSON](文件事件.ndjson)：逐条展开，标出源码行号；错误行单独提示。
- [CSV](../阅读清单.csv) / [TSV](阅读进度.tsv)：两种分隔符的表格。
- [Vue](阅读卡片.vue) / [Svelte](阅读卡片.svelte)：模板、脚本与样式分区高亮。
- [.gitignore](../代码与配置/.gitignore) / [.env](../代码与配置/.env)：规则与键值高亮，各保留一份。
- [自定义扩展名](工作区.luma-note)：按内容识别 UTF-8 文本，保存时保留扩展名。

代码与配置示例可切换源码编辑；HTML、组件、脚本和补丁在这里作为文件阅读。
GeoJSON 使用 JSON 代码预览；GIF 当前显示首帧。普通文本配置保留原文。
预览格式化只影响显示，保存仍保留源码的注释、换行和记录结构。

## 完整格式清单

同一行列出的扩展名采用相同的阅读方式。图片各编码分别提供真实文件。
'''
lines = [intro.rstrip(), ""]
for section in dict.fromkeys(entry["section"] for entry in entries):
    lines += [f"### {section}", "", "| 格式 / 语言 | 扩展名 | 示例文件 |", "| --- | --- | --- |"]
    for entry in entries:
        if entry["section"] != section:
            continue
        relative = os.path.relpath(SAMPLES / entry["path"], SAMPLES / "格式示例")
        suffixes = "、".join("`." + ext + "`" for ext in entry["extensions"]) or "按文本内容识别"
        label = Path(entry["path"]).name
        lines.append(f"| {entry['name']} | {suffixes} | [{label}](<{relative}>) |")
    lines.append("")
lines += ["## 继续阅读", "", "[欢迎页](../欢迎.md)提供搜索、图片与公式、长文导航、书签和源码编辑的功能示例。", ""]
(SAMPLES / "格式示例/格式导览.md").write_text("\n".join(lines), encoding="utf-8")

# ImageIO has no WebP encoder. Store a genuine lossless WebP derived from the same cover.
try:
    from PIL import Image
except ImportError as error:
    raise SystemExit("Refreshing WebP requires Pillow; normal Luma builds do not. Use a Python environment with Pillow installed.") from error
with Image.open(SAMPLES / "留白.png") as image:
    image.save(SAMPLES / "图片格式/阅读封面.webp", format="WEBP", lossless=True)

print(f"Updated {len(entries)} representative formats; covered {sum(len(entry['extensions']) for entry in entries)} extensions.")
