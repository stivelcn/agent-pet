#!/usr/bin/env python3
"""Guard the merged app regression baseline; intentional retirements require review."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
inventory = json.loads((root / "Tests/test-inventory.json").read_text())
missing = []
for item in inventory:
    path = root / item["file"]
    pattern = r"@Test\s+func\s+" + re.escape(item["method"]) + r"\s*\("
    if not path.exists() or not re.search(pattern, path.read_text()):
        missing.append(f'{item["file"]}:{item["method"]}')
if missing:
    raise SystemExit("缺少回归测试：\n" + "\n".join(missing))
print(f"回归测试清单核对通过：{len(inventory)} 个测试方法均保留并标记为 @Test。")
