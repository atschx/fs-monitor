#!/usr/bin/env python3
"""Render docs/guide.md into docs/guide.html for GitHub Pages. Single source: guide.md."""
from __future__ import annotations

import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MD = ROOT / "guide.md"
OUT = ROOT / "guide.html"


def inline(text: str) -> str:
    text = html.escape(text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return text


def render(md: str) -> str:
    lines = md.splitlines()
    body: list[str] = []
    in_ul = False
    in_ol = False
    in_pre = False
    paragraph: list[str] = []

    def flush_p() -> None:
        nonlocal paragraph
        if paragraph:
            body.append("<p>" + inline(" ".join(paragraph)) + "</p>")
            paragraph = []

    def close_lists() -> None:
        nonlocal in_ul, in_ol
        if in_ul:
            body.append("</ul>")
            in_ul = False
        if in_ol:
            body.append("</ol>")
            in_ol = False

    for raw in lines:
        line = raw.rstrip("\n")
        if line.startswith("```"):
            flush_p()
            close_lists()
            if in_pre:
                body.append("</code></pre>")
                in_pre = False
            else:
                body.append("<pre><code>")
                in_pre = True
            continue
        if in_pre:
            body.append(html.escape(line) + "\n")
            continue
        if not line.strip():
            flush_p()
            close_lists()
            continue
        if line.startswith("# "):
            flush_p()
            close_lists()
            body.append(f"<h1>{inline(line[2:])}</h1>")
            continue
        if line.startswith("## "):
            flush_p()
            close_lists()
            body.append(f"<h2>{inline(line[3:])}</h2>")
            continue
        if line.startswith("### "):
            flush_p()
            close_lists()
            body.append(f"<h3>{inline(line[4:])}</h3>")
            continue
        m = re.match(r"^(\d+)\.\s+(.*)$", line)
        if m:
            flush_p()
            if in_ul:
                body.append("</ul>")
                in_ul = False
            if not in_ol:
                body.append('<ol class="plain-list">')
                in_ol = True
            body.append(f"<li>{inline(m.group(2))}</li>")
            continue
        if line.startswith("- "):
            flush_p()
            if in_ol:
                body.append("</ol>")
                in_ol = False
            if not in_ul:
                body.append('<ul class="plain-list">')
                in_ul = True
            body.append(f"<li>{inline(line[2:])}</li>")
            continue
        paragraph.append(line.strip())

    flush_p()
    close_lists()
    if in_pre:
        body.append("</code></pre>")

    content = "\n".join(body)
    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>FSMonitor 使用指南</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@400;500;700&family=Sora:wght@600;700&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <div class="atmosphere" aria-hidden="true"></div>
  <header class="hero">
    <p class="brand">fs-monitor</p>
    <p class="status-chip"><a href="index.html">介绍页</a> · 正文来自 docs/guide.md</p>
  </header>
  <main>
{content}
  </main>
  <footer>
    <p><a href="index.html">返回介绍</a> · <a href="https://github.com/atschx/fs-monitor/blob/main/docs/guide.md">guide.md 源文件</a></p>
  </footer>
</body>
</html>
"""


def main() -> None:
    md = MD.read_text(encoding="utf-8")
    OUT.write_text(render(md), encoding="utf-8")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
