#!/usr/bin/env python3
import sys
import re
import os
import shutil
import subprocess


def find_handler_file():
    python_bin = os.environ.get("PYTHON_BIN", "python3")
    try:
        result = subprocess.run(
            [python_bin, "-c", "import litellm; print(litellm.__path__[0])"],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"WARNING: 无法定位 litellm 包路径: {result.stderr.strip()}")
            return None
        litellm_path = result.stdout.strip()
        handler = os.path.join(
            litellm_path,
            "responses", "litellm_completion_transformation", "handler.py"
        )
        if os.path.isfile(handler):
            return handler
        alt_dirs = [
            os.path.join(litellm_path, "responses"),
            os.path.join(litellm_path, "proxy"),
            litellm_path,
        ]
        for d in alt_dirs:
            if not os.path.isdir(d):
                continue
            for root, dirs, files in os.walk(d):
                for f in files:
                    if f == "handler.py":
                        full = os.path.join(root, f)
                        with open(full, "r", encoding="utf-8", errors="ignore") as fh:
                            c = fh.read()
                        if "acompletion_args" in c and "litellm_completion_request" in c:
                            print(f"WARNING: 标准路径不存在，找到替代: {full}")
                            return full
        print(f"WARNING: handler.py 不存在于 {litellm_path}")
        return None
    except Exception as e:
        print(f"WARNING: 定位 litellm 失败: {e}")
        return None


def is_already_patched(content):
    return (
        "acompletion_args.pop" in content
        and "completion_args.pop" in content
        and 't.get("type") == "function"' in content
    )


def _build_patch_lines(prefix):
    indent = "        "
    return [
        f'{indent}for _k in ["client_metadata", "max_output_tokens", "previous_response_id"]:',
        f"{indent}    {prefix}.pop(_k, None)",
        "",
        f"{indent}_tools = {prefix}.get('tools')",
        f"{indent}if _tools and isinstance(_tools, list):",
        f"{indent}    {prefix}['tools'] = [",
        f'{indent}        t for t in _tools if t.get("type") == "function"',
        f"{indent}    ]",
    ]


def _detect_indent(line):
    return line[:len(line) - len(line.lstrip())]


def patch_by_insertion(content):
    lines = content.split("\n")
    new_lines = []
    patched_async = False
    patched_sync = False

    for i, line in enumerate(lines):
        new_lines.append(line)

        if not patched_async and "acompletion_args.update(litellm_completion_request)" in line:
            indent = _detect_indent(line)
            for pl in _build_patch_lines("acompletion_args"):
                if pl == "":
                    new_lines.append("")
                elif pl.startswith("        "):
                    new_lines.append(indent + pl.lstrip())
                else:
                    new_lines.append(pl)
            patched_async = True

        if not patched_sync and "completion_args.update(litellm_completion_request)" in line:
            indent = _detect_indent(line)
            for pl in _build_patch_lines("completion_args"):
                if pl == "":
                    new_lines.append("")
                elif pl.startswith("        "):
                    new_lines.append(indent + pl.lstrip())
                else:
                    new_lines.append(pl)
            patched_sync = True

    if not patched_async:
        return False, "async_insert", content
    if not patched_sync:
        return False, "sync_insert", content

    return True, "ok", "\n".join(new_lines)


def patch_by_regex(content):
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

    patterns_async = [
        r"(acompletion_args\.update\(litellm_completion_request\)\s*\n)(\s*\n\s*litellm_completion_response)",
        r"(acompletion_args\.update\(litellm_completion_request\)\s*\n)(\s*\n\s*for _k in)",
    ]
    for pat in patterns_async:
        content, n = re.subn(pat, r"\1" + patch_code_async + r"\2", content, count=1)
        if n > 0:
            break
    else:
        return False, "async", content

    patterns_sync = [
        r"(completion_args\.update\(litellm_completion_request\)\s*\n)(\s*\n\s*litellm_completion_response)",
        r"(completion_args\.update\(litellm_completion_request\)\s*\n)(\s*\n\s*for _k in)",
    ]
    for pat in patterns_sync:
        content, n = re.subn(pat, r"\1" + patch_code_sync + r"\2", content, count=1)
        if n > 0:
            break
    else:
        return False, "sync", content

    return True, "ok", content


def _diagnose(content):
    has_async_update = "acompletion_args.update(litellm_completion_request)" in content
    has_sync_update = "completion_args.update(litellm_completion_request)" in content
    has_async_dict = "acompletion_args = {}" in content
    has_sync_dict = "completion_args = {}" in content
    has_class = "LiteLLMCompletionTransformationHandler" in content
    print(f"  类定义: {'有' if has_class else '无'}")
    print(f"  异步 update 行: {'有' if has_async_update else '无'}")
    print(f"  同步 update 行: {'有' if has_sync_update else '无'}")
    print(f"  异步 dict 行: {'有' if has_async_dict else '无'}")
    print(f"  同步 dict 行: {'有' if has_sync_dict else '无'}")
    if not has_async_update and not has_sync_update:
        for i, line in enumerate(content.split("\n")):
            if "acompletion_args" in line or "completion_args" in line:
                print(f"  相关行 {i}: {line.rstrip()}")


def patch_handler(filepath):
    if not os.path.isfile(filepath):
        print(f"ERROR: 文件不存在: {filepath}")
        sys.exit(1)

    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    if is_already_patched(content):
        print("OK: 已经 patch 过，跳过")
        return

    backup_path = filepath + ".bak"
    shutil.copy2(filepath, backup_path)
    print(f"备份: {backup_path}")

    ok, msg, result = patch_by_insertion(content)
    if ok:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(result)
        print(f"OK: 已 patch {filepath} (行级插入方式)")
        return
    print(f"行级插入失败 ({msg})，尝试正则匹配 ...")

    ok, msg, result = patch_by_regex(content)
    if ok:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(result)
        print(f"OK: 已 patch {filepath} (正则匹配方式)")
        return
    print(f"正则匹配也失败 ({msg})")

    shutil.copy2(backup_path, filepath)
    print(f"ERROR: 无法自动 patch，诊断信息:")
    _diagnose(content)
    print(f"")
    print(f"文件: {filepath}")
    print(f"备份: {backup_path}")
    print(f"")
    print("手动修改方法:")
    print("  在 acompletion_args.update(litellm_completion_request) 之后插入:")
    print('    for _k in ["client_metadata", "max_output_tokens", "previous_response_id"]:')
    print("        acompletion_args.pop(_k, None)")
    print("    _tools = acompletion_args.get('tools')")
    print("    if _tools and isinstance(_tools, list):")
    print('        acompletion_args["tools"] = [t for t in _tools if t.get("type") == "function"]')
    print("  同理在 completion_args.update(litellm_completion_request) 之后插入相同代码")
    print("  (把 acompletion_args 换成 completion_args)")
    sys.exit(1)


if __name__ == "__main__":
    if len(sys.argv) == 2:
        patch_handler(sys.argv[1])
    else:
        handler = find_handler_file()
        if handler:
            print(f"自动定位: {handler}")
            patch_handler(handler)
        else:
            print(f"用法: {sys.argv[0]} [handler.py 路径]")
            print("  不传参数时自动定位 litellm handler.py")
            sys.exit(1)
