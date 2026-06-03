#!/usr/bin/env python3
import sys
import re
import os
import shutil

def find_handler_file():
    python_bin = os.environ.get("PYTHON_BIN", "python3")
    try:
        import subprocess
        result = subprocess.run(
            [python_bin, "-c", "import litellm; print(litellm.__path__[0])"],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            return None
        litellm_path = result.stdout.strip()
        handler = os.path.join(
            litellm_path,
            "responses", "litellm_completion_transformation", "handler.py"
        )
        return handler if os.path.isfile(handler) else None
    except Exception:
        return None

def is_already_patched(content):
    checks = [
        "client_metadata" in content,
        "max_output_tokens" in content,
        "acompletion_args.pop" in content,
        "completion_args.pop" in content,
        't.get("type") == "function"' in content,
    ]
    return all(checks)

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
        r"(acompletion_args\.update\(litellm_completion_request\)\n)(\n\s+litellm_completion_response)",
        r"(acompletion_args\.update\(litellm_completion_request\)\n)(\n\s+for _k in)",
    ]
    for pat in patterns_async:
        content, n = re.subn(pat, r"\1" + patch_code_async + r"\2", content, count=1)
        if n > 0:
            break
    else:
        return False, "async"

    patterns_sync = [
        r"(completion_args\.update\(litellm_completion_request\)\n)(\n\s+litellm_completion_response)",
        r"(completion_args\.update\(litellm_completion_request\)\n)(\n\s+for _k in)",
    ]
    for pat in patterns_sync:
        content, n = re.subn(pat, r"\1" + patch_code_sync + r"\2", content, count=1)
        if n > 0:
            break
    else:
        return False, "sync"

    return True, content

def patch_by_insertion(content):
    lines = content.split("\n")
    new_lines = []
    patched_async = False
    patched_sync = False

    for i, line in enumerate(lines):
        new_lines.append(line)

        if not patched_async and "acompletion_args.update(litellm_completion_request)" in line:
            indent = "        "
            new_lines.append(f'{indent}for _k in ["client_metadata", "max_output_tokens", "previous_response_id"]:')
            new_lines.append(f"{indent}    acompletion_args.pop(_k, None)")
            new_lines.append("")
            new_lines.append(f"{indent}_tools = acompletion_args.get('tools')")
            new_lines.append(f"{indent}if _tools and isinstance(_tools, list):")
            new_lines.append(f"{indent}    acompletion_args['tools'] = [")
            new_lines.append(f'{indent}        t for t in _tools if t.get("type") == "function"')
            new_lines.append(f"{indent}    ]")
            patched_async = True

        if not patched_sync and "completion_args.update(litellm_completion_request)" in line:
            indent = "        "
            new_lines.append(f'{indent}for _k in ["client_metadata", "max_output_tokens", "previous_response_id"]:')
            new_lines.append(f"{indent}    completion_args.pop(_k, None)")
            new_lines.append("")
            new_lines.append(f"{indent}_tools = completion_args.get('tools')")
            new_lines.append(f"{indent}if _tools and isinstance(_tools, list):")
            new_lines.append(f"{indent}    completion_args['tools'] = [")
            new_lines.append(f'{indent}        t for t in _tools if t.get("type") == "function"')
            new_lines.append(f"{indent}    ]")
            patched_sync = True

    if not patched_async:
        return False, "async_insert"
    if not patched_sync:
        return False, "sync_insert"

    return True, "\n".join(new_lines)

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

    ok, result = patch_by_regex(content)
    if ok:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(result)
        print(f"OK: 已 patch {filepath} (正则匹配方式)")
        return
    else:
        print(f"正则匹配失败 ({result})，尝试行级插入方式 ...")

    ok, result = patch_by_insertion(content)
    if ok:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(result)
        print(f"OK: 已 patch {filepath} (行级插入方式)")
        return
    else:
        print(f"行级插入也失败 ({result})，恢复备份 ...")
        shutil.copy2(backup_path, filepath)
        print(f"ERROR: 无法自动 patch，请手动修改 {filepath}")
        print("")
        print("需要在 async_response_api_handler 的 acompletion_args.update(litellm_completion_request) 之后插入:")
        print('  for _k in ["client_metadata", "max_output_tokens", "previous_response_id"]:')
        print("      acompletion_args.pop(_k, None)")
        print("  _tools = acompletion_args.get('tools')")
        print("  if _tools and isinstance(_tools, list):")
        print('      acompletion_args["tools"] = [t for t in _tools if t.get("type") == "function"]')
        print("")
        print("同步方法 response_api_handler 同理，把 acompletion_args 换成 completion_args")
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
