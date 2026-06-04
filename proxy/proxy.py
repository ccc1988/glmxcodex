#!/usr/bin/env python3
"""
Multi-Backend Responses API Proxy for Codex Desktop

Routes to correct backend based on model name prefix:
  glm-*      → 智譜 GLM Chat Completions API
  deepseek-* → DeepSeek Chat Completions API
  gpt-*, o*  → OpenAI Responses API (direct forward)

Architecture: Codex Desktop → proxy (:18765) → backend API
"""

import json
import http.server
import socketserver
import http.client
import urllib.request
import urllib.error
import urllib.parse
import os
import sys
import logging
import ssl

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(line_buffering=True)

try:
    import certifi
    SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())
except Exception:
    SSL_CONTEXT = ssl.create_default_context()
    try:
        SSL_CONTEXT.load_default_certs()
    except Exception:
        SSL_CONTEXT = ssl._create_unverified_context()

CONFIG_PATH = os.path.expanduser("~/.claude/proxy-config.json")
PROXY_PORT = int(os.environ.get("PROXY_PORT", 18765))

BACKENDS = {}

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("proxy")


def load_config():
    global BACKENDS
    cfg = {
        "glm": {
            "label": "智谱 GLM (Zhipu AI)",
            "api_base": "https://open.bigmodel.cn/api/coding/paas/v4",
            "api_key": os.environ.get("GLM_API_KEY", ""),
        },
        "deepseek": {
            "label": "DeepSeek",
            "api_base": "https://api.deepseek.com/v1",
            "api_key": os.environ.get("DEEPSEEK_API_KEY", ""),
        },
        "openai": {
            "label": "OpenAI",
            "api_base": "https://api.openai.com/v1",
            "api_key": os.environ.get("OPENAI_API_KEY_DIRECT", ""),
        },
    }
    try:
        with open(CONFIG_PATH, "r") as f:
            user_cfg = json.load(f)
        for k, v in user_cfg.get("backends", {}).items():
            if k in cfg:
                cfg[k].update(v)
    except Exception:
        pass
    try:
        with open(os.path.expanduser("~/.claude/litellm-config.yaml"), "r") as f:
            content = f.read()
        import re
        m = re.search(r'api_key:\s*["\']?([a-zA-Z0-9_.-]+)["\']?', content)
        if m and m.group(1) != "PROXY_MANAGED" and not cfg["glm"]["api_key"]:
            cfg["glm"]["api_key"] = m.group(1)
    except Exception:
        pass
    BACKENDS = cfg
    return cfg


INSTRUCTIONS_REPLACE = {
    "glm": [
        ("based on GPT-5", "based on GLM-5.1 (智谱 AI)"),
        ("OpenAI", "智谱 AI"),
        ("GPT-5", "GLM-5.1"),
    ],
    "deepseek": [
        ("based on GPT-5", "based on DeepSeek AI"),
        ("OpenAI", "DeepSeek"),
        ("GPT-5", "DeepSeek"),
    ],
}

GLM_MODEL_NAMES = {
    "glm-5.1", "glm-5", "glm-5-turbo",
    "glm-4-plus", "glm-4", "glm-4-flash",
}

DEEPSEEK_MODEL_NAMES = {
    "deepseek-chat", "deepseek-reasoner",
    "deepseek-v3", "deepseek-r1",
    "deepseek-v4-flash",
}

OPENAI_MODEL_PREFIXES = ("gpt-", "gpt.", "o1", "o3", "o4")


def detect_backend(model_name):
    model_lower = model_name.lower() if model_name else ""
    if any(model_lower.startswith(p) for p in ("glm-", "glm4", "glm3")) or model_lower in GLM_MODEL_NAMES:
        return "glm"
    if model_lower.startswith("deepseek") or model_lower in DEEPSEEK_MODEL_NAMES:
        return "deepseek"
    if any(model_lower.startswith(p) for p in OPENAI_MODEL_PREFIXES):
        return "openai"
    return "glm"


def rewrite_instructions(instructions, backend):
    rules = INSTRUCTIONS_REPLACE.get(backend, [])
    if not rules:
        return instructions
    if isinstance(instructions, str):
        for old, new in rules:
            instructions = instructions.replace(old, new)
    elif isinstance(instructions, list):
        for inst in instructions:
            if isinstance(inst, dict) and inst.get("type") == "input_text":
                text = inst.get("text", "")
                for old, new in rules:
                    text = text.replace(old, new)
                inst["text"] = text
    return instructions


def convert_responses_to_chat(body: dict, backend: str) -> dict:
    chat_body = {}
    model = body.get("model", "glm-5.1")
    chat_body["model"] = model

    messages = []
    instructions = body.get("instructions", "")
    if instructions:
        if isinstance(instructions, str):
            messages.append({"role": "system", "content": instructions})
        elif isinstance(instructions, list):
            for inst in instructions:
                if isinstance(inst, dict):
                    if inst.get("type") == "input_text":
                        messages.append({"role": "system", "content": inst.get("text", "")})
                    elif inst.get("type") == "message":
                        role = inst.get("role", "system")
                        if role == "developer":
                            role = "system"
                        content = inst.get("content", "")
                        if isinstance(content, list):
                            texts = [c.get("text", "") for c in content if isinstance(c, dict)]
                            content = " ".join(texts)
                        messages.append({"role": role, "content": content})

    if "input" in body:
        inp = body["input"]
        if isinstance(inp, str):
            messages.append({"role": "user", "content": inp})
        elif isinstance(inp, list):
            for item in inp:
                if not isinstance(item, dict) or "type" not in item:
                    continue
                if item["type"] == "message":
                    role = item.get("role", "user")
                    if role == "developer":
                        role = "system"
                    content = item.get("content", [])
                    if isinstance(content, list):
                        texts = [c.get("text", "") for c in content if isinstance(c, dict)]
                        if texts:
                            messages.append({"role": role, "content": " ".join(texts)})
                    elif isinstance(content, str):
                        messages.append({"role": role, "content": content})
                elif item["type"] == "function_call":
                    call_id = item.get("call_id", item.get("id", ""))
                    name = item.get("name", "")
                    arguments = item.get("arguments", "{}")
                    messages.append({
                        "role": "assistant", "content": None,
                        "tool_calls": [{"id": call_id, "type": "function",
                                        "function": {"name": name, "arguments": arguments}}]
                    })
                elif item["type"] == "function_call_output":
                    call_id = item.get("call_id", "")
                    output = item.get("output", "")
                    messages.append({"role": "tool", "tool_call_id": call_id, "content": output})
        elif isinstance(inp, dict):
            for msg in inp.get("messages", inp.get("input", [])):
                role = msg.get("role", "user")
                if role == "developer":
                    role = "system"
                messages.append({"role": role, "content": msg.get("content", "")})

    chat_body["messages"] = messages

    for key in ["temperature", "top_p", "max_tokens", "stream", "frequency_penalty", "presence_penalty", "stop"]:
        if key in body:
            chat_body[key] = body[key]

    if "tools" in body:
        chat_tools = []
        for tool in body["tools"]:
            if isinstance(tool, dict):
                tt = tool.get("type", "")
                if tt in ["web_search", "code_interpreter", "file_search", "computer_use"]:
                    continue
                if tt == "function":
                    if "function" in tool:
                        chat_tools.append(tool)
                    else:
                        ct = {"type": "function", "function": {}}
                        for fk in ["name", "description", "parameters"]:
                            if fk in tool:
                                ct["function"][fk] = tool[fk]
                        chat_tools.append(ct)
        if chat_tools:
            chat_body["tools"] = chat_tools

    if "tool_choice" in body:
        chat_body["tool_choice"] = body["tool_choice"]

    return chat_body


def convert_chat_to_responses(response_body: dict) -> dict:
    outputs = []
    if "choices" in response_body:
        for choice in response_body["choices"]:
            msg = choice.get("message", {})
            content_text = msg.get("content", "")
            content = []
            if content_text:
                content.append({"type": "output_text", "text": content_text})
            if "tool_calls" in msg:
                for tc in msg["tool_calls"]:
                    content.append({
                        "type": "tool_call", "id": tc.get("id", ""),
                        "call_id": tc.get("id", ""),
                        "name": tc.get("function", {}).get("name", ""),
                        "arguments": tc.get("function", {}).get("arguments", "{}")
                    })
            outputs.append({
                "type": "message",
                "id": f"msg_{response_body.get('id', '')}",
                "status": "completed",
                "role": msg.get("role", "assistant"),
                "content": content,
            })
    return {
        "id": response_body.get("id", ""),
        "object": "response",
        "created": response_body.get("created", 0),
        "model": response_body.get("model", ""),
        "output": outputs,
        "usage": response_body.get("usage", {}),
        "status": "completed",
    }


class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        log.info(fmt, *args)

    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "backends": list(BACKENDS.keys())}).encode())
        elif self.path in ("/v4/models", "/v1/models"):
            self.handle_models()
        else:
            self.send_response(404)
            self.send_header("Connection", "close")
            self.end_headers()

    def handle_models(self):
        all_models = []
        for bid in BACKENDS:
            if bid == "glm":
                all_models.extend(["glm-5.1", "glm-5", "glm-5-turbo"])
            elif bid == "deepseek":
                all_models.extend(["deepseek-chat", "deepseek-reasoner"])
        models = [{"id": n, "object": "model", "created": 1700000000, "owned_by": "proxy"} for n in all_models]
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(json.dumps({"object": "list", "data": models}).encode())

    def do_POST(self):
        if self.path.endswith("/responses"):
            self.handle_responses()
        elif self.path.endswith("/chat/completions"):
            self.forward_request("POST")
        else:
            self.forward_request("POST")

    def handle_responses(self):
        try:
            content_length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_length))
            model = body.get("model", "?")
            backend = detect_backend(model)
            is_stream = body.get("stream", False)

            log.info(f"Model: {model} → backend: {backend} (stream={is_stream})")

            instructions = body.get("instructions", "")
            if instructions:
                body["instructions"] = rewrite_instructions(instructions, backend)

            if backend == "openai":
                self.forward_to_openai(body, is_stream)
            else:
                self.handle_chat_backend(body, backend, is_stream)

        except Exception as e:
            log.error(f"Proxy error: {e}")
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())

    def handle_chat_backend(self, body, backend, is_stream):
        chat_body = convert_responses_to_chat(body, backend)
        cfg = BACKENDS.get(backend, BACKENDS.get("glm", {}))
        api_base = cfg.get("api_base", "")
        api_key = cfg.get("api_key", "")

        if not api_base or not api_key:
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(json.dumps({"error": f"No config for backend: {backend}"}).encode())
            return

        log.info(f"→ {backend}: {api_base}/chat/completions msg={len(chat_body.get('messages',[]))}")

        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
            "Accept": "text/event-stream" if is_stream else "application/json",
        }
        url = urllib.parse.urlparse(api_base)
        conn = http.client.HTTPSConnection(url.netloc, timeout=120, context=SSL_CONTEXT)
        try:
            conn.request("POST", f"{url.path}/chat/completions",
                         body=json.dumps(chat_body).encode(), headers=headers)
            resp = conn.getresponse()
            if resp.status != 200:
                err = resp.read().decode()
                log.error(f"{backend} error {resp.status}: {err[:300]}")
                self.send_response(resp.status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(err.encode())
                return
            if is_stream:
                self.stream_response(resp)
            else:
                data = json.loads(resp.read())
                converted = convert_chat_to_responses(data)
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(json.dumps(converted).encode())
        finally:
            conn.close()

    def forward_to_openai(self, body, is_stream):
        cfg = BACKENDS.get("openai", {})
        api_base = cfg.get("api_base", "https://api.openai.com/v1")
        api_key = cfg.get("api_key", "")

        if not api_key:
            log.info("No OpenAI key configured, passing through to public API")
            api_key = "dummy"

        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
            "Accept": "text/event-stream" if is_stream else "application/json",
        }
        url = urllib.parse.urlparse(api_base)
        conn = http.client.HTTPSConnection(url.netloc, timeout=120, context=SSL_CONTEXT)
        log.info(f"→ openai: {api_base}/responses")
        try:
            conn.request("POST", f"{url.path}/responses",
                         body=json.dumps(body).encode(), headers=headers)
            resp = conn.getresponse()
            if resp.status != 200:
                err = resp.read().decode()
                log.error(f"OpenAI error {resp.status}: {err[:300]}")
                self.send_response(resp.status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(err.encode())
                return
            if is_stream:
                self.stream_response(resp)
            else:
                data = resp.read()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(data)
        finally:
            conn.close()

    def stream_response(self, upstream_response):
        self.seq = 0
        self.item_id = None
        self.response_id = None
        self.created_at = None
        self.model_name = None
        self.full_content = ""
        self.tool_calls = {}

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()

        chunk_count = 0
        try:
            buf = b""
            while True:
                ch = upstream_response.read(1)
                if not ch:
                    break
                buf += ch
                if ch == b"\n":
                    line = buf.strip()
                    buf = b""
                    if not line:
                        continue
                    for cl in self._convert_line(line):
                        self.wfile.write(cl)
                        self.wfile.flush()
                        chunk_count += 1
            log.info(f"Stream done: {chunk_count} chunks")
        except Exception as e:
            log.error(f"Stream error: {e}")

    def _convert_line(self, line: bytes):
        results = []
        if not line.startswith(b"data: "):
            return [line + b"\n"]
        data = line[6:].strip()
        if data == b"[DONE]":
            outputs = []
            if self.full_content and self.item_id:
                outputs.append({"type": "message", "id": self.item_id, "status": "completed",
                                "role": "assistant", "content": [{"type": "output_text", "text": self.full_content}]})
            for tc_data in self.tool_calls.values():
                outputs.append({"type": "function_call", "id": f"fc_{tc_data['id']}",
                                "call_id": tc_data["id"], "name": tc_data["name"],
                                "arguments": tc_data["arguments"], "status": "completed"})
            if self.response_id:
                ev = {"type": "response.completed", "sequence_number": self.seq,
                      "response": {"id": self.response_id, "object": "response",
                                   "created_at": self.created_at or 0, "model": self.model_name or "",
                                   "output": outputs, "status": "completed"}}
                self.seq += 1
                results.append(f"event: response.completed\ndata: {json.dumps(ev)}\n\n".encode())
            results.append(b"data: [DONE]\n\n")
            return results

        try:
            chunk = json.loads(data)
            if not self.item_id:
                rid = chunk.get("id", "")
                if not rid.startswith("resp_"):
                    rid = f"resp_{rid}"
                self.response_id = rid
                self.created_at = chunk.get("created", 0)
                self.model_name = chunk.get("model", "")
                self.item_id = f"msg_{rid}"
                for ev in [
                    {"type": "response.created", "response": {"id": rid, "object": "response",
                     "created_at": self.created_at, "model": self.model_name, "output": [], "status": "in_progress"}},
                    {"type": "response.output_item.added", "output_index": 0,
                     "item": {"type": "message", "id": self.item_id, "status": "in_progress", "role": "assistant", "content": []}},
                    {"type": "response.content_part.added", "output_index": 0, "content_index": 0,
                     "item_id": self.item_id, "content_part": {"type": "output_text", "text": ""}},
                ]:
                    self.seq += 1
                    ev["sequence_number"] = self.seq
                    results.append(f"event: {ev['type']}\ndata: {json.dumps(ev)}\n\n".encode())

            for choice in chunk.get("choices", []):
                delta = choice.get("delta", {})
                content = delta.get("content", "")
                if content:
                    self.full_content += content
                    ev = {"type": "response.output_text.delta", "sequence_number": self.seq,
                          "output_index": 0, "content_index": 0, "item_id": self.item_id,
                          "delta": content, "logprobs": []}
                    self.seq += 1
                    results.append(f"event: response.output_text.delta\ndata: {json.dumps(ev)}\n\n".encode())

                for tc in delta.get("tool_calls", []):
                    idx = tc.get("index", 0)
                    tid = tc.get("id", "")
                    fn = tc.get("function", {})
                    if idx not in self.tool_calls:
                        self.tool_calls[idx] = {"id": tid, "name": fn.get("name", ""), "arguments": ""}
                        ev = {"type": "response.output_item.added", "sequence_number": self.seq,
                              "output_index": idx + 1, "item": {"type": "function_call",
                              "id": f"fc_{tid}", "call_id": tid, "name": fn.get("name", ""),
                              "arguments": "", "status": "in_progress"}}
                        self.seq += 1
                        results.append(f"event: response.output_item.added\ndata: {json.dumps(ev)}\n\n".encode())
                    args = fn.get("arguments", "")
                    if args:
                        self.tool_calls[idx]["arguments"] += args
                        ev = {"type": "response.function_call_arguments.delta", "sequence_number": self.seq,
                              "output_index": idx + 1, "item_id": f"fc_{tid}", "delta": args, "call_id": tid}
                        self.seq += 1
                        results.append(f"event: response.function_call_arguments.delta\ndata: {json.dumps(ev)}\n\n".encode())

                fr = choice.get("finish_reason")
                if fr:
                    if fr == "tool_calls":
                        for idx, td in self.tool_calls.items():
                            for ev in [
                                {"type": "response.function_call_arguments.done", "output_index": idx + 1,
                                 "item_id": f"fc_{td['id']}", "arguments": td["arguments"], "call_id": td["id"]},
                                {"type": "response.output_item.done", "output_index": idx + 1,
                                 "item": {"type": "function_call", "id": f"fc_{td['id']}",
                                          "call_id": td["id"], "name": td["name"],
                                          "arguments": td["arguments"], "status": "completed"}},
                            ]:
                                self.seq += 1
                                ev["sequence_number"] = self.seq
                                results.append(f"event: {ev['type']}\ndata: {json.dumps(ev)}\n\n".encode())
                    if self.full_content:
                        for ev in [
                            {"type": "response.output_text.done", "output_index": 0, "content_index": 0,
                             "item_id": self.item_id, "text": self.full_content},
                            {"type": "response.content_part.done", "output_index": 0, "content_index": 0,
                             "item_id": self.item_id, "content_part": {"type": "output_text", "text": self.full_content}},
                            {"type": "response.output_item.done", "output_index": 0,
                             "item": {"type": "message", "id": self.item_id, "status": "completed",
                                      "role": "assistant", "content": [{"type": "output_text", "text": self.full_content}]}},
                        ]:
                            self.seq += 1
                            ev["sequence_number"] = self.seq
                            results.append(f"event: {ev['type']}\ndata: {json.dumps(ev)}\n\n".encode())
            return results
        except json.JSONDecodeError as e:
            log.error(f"Parse error: {e}")
            return [line + b"\n"]

    def forward_request(self, method):
        try:
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else None
            backend = "glm"
            cfg = BACKENDS.get(backend, {})
            api_key = cfg.get("api_key", "")
            api_base = cfg.get("api_base", "https://open.bigmodel.cn/api/coding/paas/v4")

            headers = {"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"}
            path = self.path
            for pfx in ["/v4/", "/v1/"]:
                if path.startswith(pfx):
                    path = path[len(pfx) - 1:]
                    break

            req = urllib.request.Request(f"{api_base}{path}", data=body, headers=headers, method=method)
            with urllib.request.urlopen(req, timeout=30, context=SSL_CONTEXT) as resp:
                data = resp.read()
                self.send_response(200)
                self.send_header("Content-Type", resp.headers.get("Content-Type", "application/json"))
                self.end_headers()
                self.wfile.write(data)
        except Exception as e:
            log.error(f"Forward error: {e}")
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())


def main():
    load_config()
    with ThreadingHTTPServer(("", PROXY_PORT), ProxyHandler) as httpd:
        log.info(f"Multi-backend proxy on :{PROXY_PORT}")
        for bid, cfg in BACKENDS.items():
            key = cfg.get("api_key", "")
            has_key = len(key) > 4 and key != "PROXY_MANAGED"
            log.info(f"  {bid}: {cfg.get('label','?')} | key={'YES' if has_key else 'NO'}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            log.info("Shutting down...")


if __name__ == "__main__":
    main()
