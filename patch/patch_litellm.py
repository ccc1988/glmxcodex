#!/usr/bin/env python3
import sys
import re

def patch_handler(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    if "Patch: 过滤" in content:
        print("已经 patch 过，跳过")
        return

    patch_code_async = """
        for _k in ["client_metadata", "max_output_tokens", "previous_response_id"]:
            acompletion_args.pop(_k, None)

        _tools = acompletion_args.get("tools")
        if _tools and isinstance(_tools, list):
            acompletion_args["tools"] = [
                t for t in _tools if t.get("type") == "function"
            ]
"""

    patch_code_sync = """
        for _k in ["client_metadata", "max_output_tokens", "previous_response_id"]:
            completion_args.pop(_k, None)

        _tools = completion_args.get("tools")
        if _tools and isinstance(_tools, list):
            completion_args["tools"] = [
                t for t in _tools if t.get("type") == "function"
            ]
"""

    pattern_async = r"(acompletion_args\.update\(litellm_completion_request\)\n)(\n\s+litellm_completion_response)"
    replacement_async = r"\1" + patch_code_async + r"\2"
    content, n1 = re.subn(pattern_async, replacement_async, content, count=1)
    if n1 == 0:
        print("ERROR: 未找到异步方法 patch 点")
        sys.exit(1)

    pattern_sync = r"(completion_args\.update\(litellm_completion_request\)\n)(\n\s+litellm_completion_response)"
    replacement_sync = r"\1" + patch_code_sync + r"\2"
    content, n2 = re.subn(pattern_sync, replacement_sync, content, count=1)
    if n2 == 0:
        print("ERROR: 未找到同步方法 patch 点")
        sys.exit(1)

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"OK: 已 patch {filepath} (异步方法 + 同步方法)")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <handler.py 路径>")
        sys.exit(1)
    patch_handler(sys.argv[1])
