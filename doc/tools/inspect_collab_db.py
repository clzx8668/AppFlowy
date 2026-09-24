"""只读检查 AppFlowy 本地 collab 库（RocksDB）内容。

用途：真机上"插入内容 → 正常退出 → 重启"之后，从数据层确认内容是否真的落库，
避免依赖 adb 注入文本/截图等不可靠手段。

用法：
    1) 拉取数据库（二进制定向，务必用 exec-out + 重定向）：
       adb exec-out run-as io.appflowy.appflowy tar -cf - \
           files/data_dev/<workspace_id>/collab_db > collab_db.tar
       tar -xf collab_db.tar
    2) python inspect_collab_db.py <collab_db 目录> [--grep 关键字] [--dump-key 键]

依赖：pip install rocksdict
"""

from __future__ import annotations

import argparse
import ast
import json
import re
import sys
from pathlib import Path


try:  # Windows 控制台默认 GBK，统一按 UTF-8 输出，避免中文/二进制片段报错
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # pragma: no cover
    pass


def open_ro(path: Path):
    from rocksdict import Rdict, AccessType

    return Rdict(str(path), access_type=AccessType.read_only())


def to_text(value: bytes) -> str:
    return value.decode("utf-8", errors="replace")


def parse_key(spec: str) -> bytes:
    """key 支持三种写法：hex:0101... / b"..." / 普通 utf-8 字符串。"""
    if spec.startswith("hex:"):
        return bytes.fromhex(spec[4:])
    if spec[:2] in ("b'", 'b"'):
        return ast.literal_eval(spec)
    return spec.encode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("db", help="collab_db 目录")
    parser.add_argument("--grep", action="append", default=[],
                        help="在 value 中查找的关键字（可多次指定）")
    parser.add_argument("--dump-key", action="append", default=[],
                        help="打印该 key 的完整 value（可多次指定）")
    parser.add_argument("--strings-key", action="append", default=[],
                        help="按可读片段打印该 key 的 value（可多次指定）")
    parser.add_argument("--min-run", type=int, default=3,
                        help="--strings-key 时视为可读片段的最小长度")
    parser.add_argument("--list", action="store_true", help="列出所有 key 与长度")
    parser.add_argument("--max-snippet", type=int, default=240)
    args = parser.parse_args()

    path = Path(args.db)
    if not path.is_dir():
        print(f"目录不存在: {path}", file=sys.stderr)
        return 2

    db = open_ro(path)
    entries = list(db.items())
    print(f"共 {len(entries)} 条记录")

    if args.list:
        for key, value in sorted(entries, key=lambda kv: -len(kv[1])):
            print(f"  hex:{key.hex()}  {len(value):8d} bytes")

    needles = [(n, n.encode("utf-8")) for n in args.grep]
    if needles:
        for name, needle in needles:
            total = 0
            for key, value in entries:
                hit = value.count(needle)
                if hit:
                    total += hit
                    idx = value.find(needle)
                    start = max(0, idx - args.max_snippet // 2)
                    snippet = to_text(value[start:start + args.max_snippet])
                    print(f"[命中] {name!r} in {key!r} x{hit}")
                    print(f"       …{snippet}…")
            if total == 0:
                print(f"[未命中] {name!r}（该记录数为 0）")

    for wanted in args.dump_key:
        key = parse_key(wanted)
        value = db.get(key)
        if value is None:
            print(f"[无此 key] {wanted}")
            continue
        print(f"==== {wanted} ({len(value)} bytes) ====")
        text = to_text(value)
        try:
            print(json.dumps(json.loads(text), ensure_ascii=False, indent=2)[:8000])
        except Exception:
            print(text[:8000])

    for wanted in args.strings_key:
        key = parse_key(wanted)
        value = db.get(key)
        if value is None:
            print(f"[无此 key] {wanted}")
            continue
        print(f"==== strings of {wanted} ({len(value)} bytes) ====")
        run = re.compile(rb"[ -~]{%d,}" % args.min_run)
        for match in run.finditer(value):
            print(f"  @{match.start():6d} {match.group().decode('ascii')}")

    db.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
