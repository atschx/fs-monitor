#!/usr/bin/env bash
# 准备、增长并清理一个隔离的临时目录。
# 目录里的文件都以【测试数据】标记。脚本不会扫描用户主目录，也不会删除没有标记的路径。
set -euo pipefail

MARK='【测试数据】这是 FSMonitor 的隔离演示或测试夹具，不是用户数据。'
MARKER_NAME='.fs-monitor-demo-marker'

usage() {
  cat <<'EOF'
用法:
  scripts/isolated-demo.sh prepare
  scripts/isolated-demo.sh grow <目录>
  scripts/isolated-demo.sh cleanup <目录>
  scripts/isolated-demo.sh self-check

prepare 只创建临时目录和测试数据，不会启动应用。
grow 只往该临时目录追加测试数据。
cleanup 只删除带有标记文件、且路径包含 fs-monitor-demo 的目录。
EOF
}

require_marked_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "不是目录: $dir" >&2
    exit 1
  fi
  if [[ ! -f "$dir/$MARKER_NAME" ]]; then
    echo "拒绝操作：缺少 $MARKER_NAME，这不是本脚本创建的演示目录。" >&2
    exit 1
  fi
  case "$dir" in
    *fs-monitor-demo*) ;;
    *)
      echo "拒绝操作：路径不包含 fs-monitor-demo。" >&2
      exit 1
      ;;
  esac
  local resolved
  resolved="$(cd "$dir" && pwd)"
  case "$resolved" in
    /|/Users|/Users/*|/home)
      echo "拒绝操作：路径过于宽泛。" >&2
      exit 1
      ;;
  esac
}

prepare() {
  local root
  root="$(mktemp -d "${TMPDIR:-/tmp}/fs-monitor-demo.XXXXXX")"
  printf '%s\n' "$MARK" > "$root/$MARKER_NAME"
  mkdir -p "$root/logs" "$root/data"
  {
    printf '%s\n' "$MARK"
    printf '这是日志夹具。\n'
  } > "$root/logs/app.log"
  {
    printf '%s\n' "$MARK"
    dd if=/dev/zero bs=1024 count=4 2>/dev/null
  } > "$root/data/cache.bin"
  printf '%s\n' "$root"
}

grow() {
  local dir="$1"
  require_marked_dir "$dir"
  {
    printf '\n%s\n' "$MARK"
    dd if=/dev/zero bs=1024 count=1024 2>/dev/null
  } >> "$dir/data/cache.bin"
  {
    printf '%s\n' "$MARK"
    printf '监控窗口内新增的测试日志。\n'
  } > "$dir/logs/new.log"
  echo "已向测试目录追加数据: $dir"
}

cleanup() {
  local dir="$1"
  require_marked_dir "$dir"
  local resolved
  resolved="$(cd "$dir" && pwd)"
  rm -rf "$resolved"
  echo "已删除测试目录: $resolved"
}

self_check() {
  local dir size_before size_after
  dir="$(prepare)"
  require_marked_dir "$dir"
  grep -q '【测试数据】' "$dir/logs/app.log"
  size_before="$(wc -c < "$dir/data/cache.bin")"
  grow "$dir"
  size_after="$(wc -c < "$dir/data/cache.bin")"
  if [[ "$size_after" -le "$size_before" ]]; then
    echo "self-check 失败：cache.bin 没有变大" >&2
    exit 1
  fi
  [[ -f "$dir/logs/new.log" ]]
  cleanup "$dir"
  if [[ -d "$dir" ]]; then
    echo "self-check 失败：目录仍在" >&2
    exit 1
  fi
  echo "self-check 完成。这只检查测试数据脚本，不是 macOS 应用构建。"
}

command="${1:-}"
case "$command" in
  prepare) prepare ;;
  grow)
    [[ $# -eq 2 ]] || { usage; exit 1; }
    grow "$2"
    ;;
  cleanup)
    [[ $# -eq 2 ]] || { usage; exit 1; }
    cleanup "$2"
    ;;
  self-check) self_check ;;
  *) usage; exit 1 ;;
esac
