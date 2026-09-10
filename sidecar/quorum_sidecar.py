"""The bridge between Quorum (Elixir) and the AI providers.

Quorum never speaks to a provider itself. This service holds the keys, drives
every provider through KeyCall, and answers one normalized /generate call on
localhost. Providers are data: they live in the key file, and no provider name
appears in this code.

Run it beside the app:

    pip install -r requirements.txt
    QUORUM_SIDECAR_TOKEN=$(openssl rand -hex 16) python3 quorum_sidecar.py \
        --keys ../project/keys.toml

The token guards the port from anything else on the machine; give Quorum the
same value in the same variable. Keys never leave this process: /health names
targets and models, never credentials.
"""

import argparse
import json
import os
import sys
import threading

try:
    import tomllib
except ModuleNotFoundError:  # tomllib arrived in Python 3.11
    import tomli as tomllib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from keycall import KeyCall, KeyCallError, Message, TextInput

MAX_BODY_BYTES = 64 * 1024


def load_targets(path):
    """The [[targets]] entries of the key file, minus unfilled placeholders."""
    with open(path, "rb") as f:
        data = tomllib.load(f)

    targets = []
    for entry in data.get("targets", []):
        if not entry.get("provider") or not entry.get("key"):
            continue
        if "REPLACE" in entry["key"]:
            continue
        entry.setdefault("name", entry["provider"])
        targets.append(entry)
    return targets


def order_candidates(models):
    """KeyCall verify's own ordering, restated: newest first where the provider
    dates every model it lists, and otherwise provider-maintained `-latest`
    aliases ahead of the provider's raw order, because an undated list's front
    can be entirely retired models. sorted() is stable, so ties keep the
    provider's order and the result is deterministic per list."""
    dated = [m for m in models if m.released_at is not None]
    if dated and len(dated) == len(models):
        return sorted(models, key=lambda m: m.released_at, reverse=True)
    return sorted(models, key=lambda m: not m.id.lower().endswith("-latest"))


# A refused credential ends the walk: no other model fares better with a key
# the provider rejects. Every other error is treated as model-scoped and the
# next candidate gets its turn, which is the rule KeyCall's verify applies.
CREDENTIAL_FAILURES = {"INVALID_API_KEY", "PERMISSION_DENIED"}
MAX_MODEL_ATTEMPTS = 4


class Target:
    """One credential, its client, and the models to try for it, in order.

    A `model =` line in the key file pins the choice outright. Otherwise the
    provider's live list is walked front to back per request kind, and the
    first model that answers is remembered — a model can serve plain text yet
    refuse structured output, so plain and schema calls each keep their own.
    """

    def __init__(self, entry):
        self.name = entry["name"]
        self.provider = entry["provider"]
        self.pinned_model = entry.get("model")
        self._entry = entry
        self._client = None
        self._candidates = None
        self._working = {}
        self._lock = threading.Lock()

    def client(self):
        if self._client is None:
            kwargs = {"provider": self._entry["provider"], "api_key": self._entry["key"]}
            for passthrough in ("protocol", "base_url"):
                if self._entry.get(passthrough):
                    kwargs[passthrough] = self._entry[passthrough]
            self._client = KeyCall(**kwargs)
        return self._client

    def candidates(self, kind):
        with self._lock:
            if self._candidates is None:
                if self.pinned_model:
                    self._candidates = [self.pinned_model]
                else:
                    models = self.client().list_models().models
                    if not models:
                        raise LookupError(f"target {self.name} lists no text models")
                    self._candidates = [m.id for m in order_candidates(models)]

            working = self._working.get(kind)
            rest = [c for c in self._candidates if c != working]
            return ([working] + rest if working else rest)[:MAX_MODEL_ATTEMPTS]

    def remember(self, kind, model_id):
        with self._lock:
            self._working[kind] = model_id


def strip_additional_properties(schema):
    """The same JSON schema minus every additionalProperties key.

    One provider requires the key and another refuses it at any depth, so a
    single schema can't satisfy both. KeyCall raises before the network when a
    schema won't fly; the retry reacts to that error rather than naming any
    provider here.
    """
    if isinstance(schema, dict):
        return {
            k: strip_additional_properties(v)
            for k, v in schema.items()
            if k != "additionalProperties"
        }
    if isinstance(schema, list):
        return [strip_additional_properties(v) for v in schema]
    return schema


def generate_with_schema_fallback(client, model, messages, kwargs):
    try:
        return client.generate_text(model=model, messages=messages, **kwargs)
    except KeyCallError as error:
        schema = kwargs.get("response_schema")
        if schema is None or "additionalProperties" not in str(error):
            raise
        retry = dict(kwargs, response_schema=strip_additional_properties(schema))
        return client.generate_text(model=model, messages=messages, **retry)


class Handler(BaseHTTPRequestHandler):
    server_version = "QuorumSidecar/1.0"
    targets = {}
    token = None

    def log_message(self, fmt, *args):
        sys.stderr.write("sidecar: %s\n" % (fmt % args))

    def _send(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self):
        return self.headers.get("X-Quorum-Token", "") == self.token

    def do_GET(self):
        if not self._authorized():
            return self._send(401, {"error": "unauthorized"})
        if self.path != "/health":
            return self._send(404, {"error": "not_found"})

        return self._send(
            200,
            {
                "ok": True,
                "targets": [
                    {"name": t.name, "provider": t.provider} for t in self.targets.values()
                ],
            },
        )

    def do_POST(self):
        if not self._authorized():
            return self._send(401, {"error": "unauthorized"})
        if self.path != "/generate":
            return self._send(404, {"error": "not_found"})

        length = int(self.headers.get("Content-Length", 0))
        if length > MAX_BODY_BYTES:
            return self._send(413, {"error": "too_large"})
        try:
            request = json.loads(self.rfile.read(length))
        except (json.JSONDecodeError, ValueError):
            return self._send(400, {"error": "bad_json"})

        prompt = request.get("prompt")
        if not prompt or not isinstance(prompt, str):
            return self._send(400, {"error": "missing_prompt"})

        target = self._pick_target(request.get("target"))
        if target is None:
            return self._send(400, {"error": "unknown_target"})

        messages = []
        if request.get("system"):
            messages.append(Message(role="system", content=[TextInput(text=request["system"])]))
        messages.append(Message(role="user", content=[TextInput(text=prompt)]))

        kwargs = {
            "max_output_tokens": int(request.get("max_output_tokens", 400)),
        }
        # Sampling is left to the model unless the caller sets it: several
        # current models pin temperature and refuse any other explicit value,
        # so a cross-provider default here would refuse whole providers.
        if request.get("temperature") is not None:
            kwargs["temperature"] = float(request["temperature"])
        if request.get("schema") is not None:
            kwargs["response_schema"] = request["schema"]

        kind = "schema" if request.get("schema") is not None else "plain"
        result = model = None
        last_error = None
        try:
            for model_id in target.candidates(kind):
                try:
                    result = generate_with_schema_fallback(
                        target.client(), model_id, messages, kwargs
                    )
                    model = model_id
                    target.remember(kind, model_id)
                    break
                except KeyCallError as error:
                    last_error = error
                    if error.code.name in CREDENTIAL_FAILURES:
                        break
        except Exception as error:  # a target that can't list, a dead socket
            return self._send(502, {"error": "sidecar", "message": str(error)})

        if result is None:
            return self._send(502, {"error": "provider", "message": str(last_error)})

        usage = result.usage
        return self._send(
            200,
            {
                "text": result.text,
                "target": target.name,
                "provider": target.provider,
                "model": model,
                "input_tokens": getattr(usage, "input_tokens", None) if usage else None,
                "output_tokens": getattr(usage, "output_tokens", None) if usage else None,
                "elapsed_ms": result.round_trip_duration_ms,
                "finish_reason": str(result.finish_reason) if result.finish_reason else None,
            },
        )

    def _pick_target(self, name):
        if name:
            return self.targets.get(name)
        return next(iter(self.targets.values()), None)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keys", required=True, help="Path to the keys TOML")
    parser.add_argument("--port", type=int, default=4747)
    args = parser.parse_args()

    token = os.environ.get("QUORUM_SIDECAR_TOKEN")
    if not token:
        sys.exit("Set QUORUM_SIDECAR_TOKEN before starting; Quorum must hold the same value.")

    targets = load_targets(args.keys)
    if not targets:
        sys.exit(f"No usable targets in {args.keys}. Fill in a key first.")

    Handler.targets = {t["name"]: Target(t) for t in targets}
    Handler.token = token

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    names = ", ".join(Handler.targets)
    print(f"Quorum sidecar on 127.0.0.1:{args.port}, targets: {names}")
    server.serve_forever()


if __name__ == "__main__":
    main()
