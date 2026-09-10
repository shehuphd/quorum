"""The bridge between Quorum (Elixir) and the AI providers.

Quorum never speaks to a provider itself. This service holds the keys, drives
every provider through KeyCall, and answers a small localhost API: one
normalized /generate, plus the key management the settings screen offers.
Providers are data: they live in the key file, and no provider name appears
in this code.

Run it beside the app:

    pip install -r requirements.txt
    QUORUM_SIDECAR_TOKEN=$(openssl rand -hex 16) python3 quorum_sidecar.py \
        --keys ../project/keys.toml

The token guards the port from anything else on the machine; give Quorum the
same value in the same variable. Keys never leave this process whole: every
listing shows the first four characters and asterisks, nothing more.
"""

import argparse
import json
import os
import re
import sys
import threading

try:
    import tomllib
except ModuleNotFoundError:  # tomllib arrived in Python 3.11
    import tomli as tomllib

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from keycall import KeyCall, KeyCallError, Message, TextInput

MAX_BODY_BYTES = 64 * 1024

# A refused credential ends a model walk: no other model fares better with a
# key the provider rejects. Every other error is treated as model-scoped and
# the next candidate gets its turn, the rule KeyCall's verify applies.
CREDENTIAL_FAILURES = {"INVALID_API_KEY", "PERMISSION_DENIED"}
MAX_MODEL_ATTEMPTS = 4


def text_providers():
    """The providers a Quorum key can be for: every one the catalog knows,
    minus the streaming-transcription platforms, which have no text models.
    Read from KeyCall's own catalog so a provider added there appears here
    without an edit; the registry module is the same one KeyCall's viewer
    reads for its key form."""
    try:
        from keycall._registry import providers_with, supported_providers

        speech = providers_with("streaming_transcription")
        return [p for p in supported_providers() if p not in speech]
    except Exception:
        return []


def key_hint(key):
    """The first four characters and asterisks. Enough to tell keys apart,
    never enough to matter."""
    return key[:4] + "*" * 12


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
        self.entry = entry
        self._client = None
        self._candidates = None
        self._working = {}
        self._lock = threading.Lock()

    def client(self):
        if self._client is None:
            kwargs = {"provider": self.entry["provider"], "api_key": self.entry["key"]}
            for passthrough in ("protocol", "base_url"):
                if self.entry.get(passthrough):
                    kwargs[passthrough] = self.entry[passthrough]
            self._client = KeyCall(**kwargs)
        return self._client

    def models(self):
        """Every usable text model for this key, in the walk's own order.
        KeyCall's listing already returns text models only and withholds the
        ones its catalog records as shut down, which is what makes this list
        safe to put straight into a picker."""
        return [m.id for m in order_candidates(self.client().list_models().models)]

    def candidates(self, kind):
        with self._lock:
            if self._candidates is None:
                if self.pinned_model:
                    self._candidates = [self.pinned_model]
                else:
                    listed = self.models()
                    if not listed:
                        raise LookupError(f"target {self.name} lists no text models")
                    self._candidates = listed

            working = self._working.get(kind)
            rest = [c for c in self._candidates if c != working]
            return ([working] + rest if working else rest)[:MAX_MODEL_ATTEMPTS]

    def remember(self, kind, model_id):
        with self._lock:
            self._working[kind] = model_id


class KeyFile:
    """The TOML file of targets, owned by this process: read on change, and
    rewritten whole on every edit. Hand-written comments don't survive a
    rewrite, which the file's own header says."""

    HEADER = (
        "# Quorum's AI provider keys, in KeyCall's TOML shape, so\n"
        "#   keycall verify --source ./project/keys.toml\n"
        "# checks the same file the sidecar reads.\n"
        "#\n"
        "# Managed by the sidecar: the settings screen edits it through the\n"
        "# sidecar's API and rewrites it whole, so comments here don't last.\n"
        "# Gitignored. chmod 600. Keys never appear in any API response.\n"
    )

    def __init__(self, path):
        self.path = path
        self.lock = threading.Lock()
        self.mtime = None
        self.targets = {}

    def refresh(self):
        """Reload when the file changed underneath, so keys edited by hand
        or by `keycall verify --source` fixes go live without a restart."""
        with self.lock:
            try:
                mtime = os.stat(self.path).st_mtime_ns
            except FileNotFoundError:
                self.mtime, self.targets = None, {}
                return

            if mtime == self.mtime:
                return
            self.mtime = mtime
            self.targets = {t["name"]: Target(t) for t in self._load()}

    def _load(self):
        with open(self.path, "rb") as f:
            data = tomllib.load(f)

        loaded = []
        for entry in data.get("targets", []):
            if not entry.get("provider") or not entry.get("key"):
                continue
            if "REPLACE" in entry["key"]:
                continue
            entry.setdefault("name", entry["provider"])
            loaded.append(entry)
        return loaded

    def upsert(self, entry):
        with self.lock:
            entries = [t.entry for t in self.targets.values() if t.name != entry["name"]]
            entries.append(entry)
            self._write(entries)

    def update_model(self, name, model):
        with self.lock:
            target = self.targets.get(name)
            if target is None:
                return False
            entry = dict(target.entry)
            if model:
                entry["model"] = model
            else:
                entry.pop("model", None)
            entries = [t.entry for t in self.targets.values() if t.name != name]
            entries.append(entry)
            self._write(entries)
            return True

    def remove(self, name):
        with self.lock:
            if name not in self.targets:
                return False
            self._write([t.entry for t in self.targets.values() if t.name != name])
            return True

    def _write(self, entries):
        lines = [self.HEADER]
        for entry in entries:
            lines.append("\n[[targets]]")
            for field in ("provider", "name", "key", "model", "protocol", "base_url"):
                if entry.get(field):
                    lines.append(f'{field} = "{self._escape(entry[field])}"')
        text = "\n".join(lines) + "\n"

        tmp = self.path + ".tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.replace(tmp, self.path)
        self.mtime = None  # next refresh() reloads

    @staticmethod
    def _escape(value):
        return str(value).replace("\\", "\\\\").replace('"', '\\"')


class Handler(BaseHTTPRequestHandler):
    server_version = "QuorumSidecar/2.0"
    keyfile = None
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

    def _body(self):
        length = int(self.headers.get("Content-Length", 0))
        if length > MAX_BODY_BYTES:
            return None
        try:
            return json.loads(self.rfile.read(length))
        except (json.JSONDecodeError, ValueError):
            return None

    def do_GET(self):
        if not self._authorized():
            return self._send(401, {"error": "unauthorized"})
        self.keyfile.refresh()

        if self.path == "/health":
            return self._send(
                200,
                {
                    "ok": True,
                    "targets": [
                        {"name": t.name, "provider": t.provider}
                        for t in self.keyfile.targets.values()
                    ],
                },
            )

        if self.path == "/providers":
            return self._send(200, {"providers": text_providers()})

        if self.path == "/targets":
            rows = []
            for target in self.keyfile.targets.values():
                row = {
                    "name": target.name,
                    "provider": target.provider,
                    "key_hint": key_hint(target.entry["key"]),
                    "model": target.pinned_model,
                }
                try:
                    row["models"] = target.models()
                except Exception as error:
                    row["models"] = []
                    row["error"] = str(error)
                rows.append(row)
            return self._send(200, {"targets": rows})

        return self._send(404, {"error": "not_found"})

    def do_POST(self):
        if not self._authorized():
            return self._send(401, {"error": "unauthorized"})
        self.keyfile.refresh()

        if self.path == "/generate":
            return self._generate()
        if self.path == "/targets":
            return self._put_target()

        pin = re.fullmatch(r"/targets/([^/]+)/model", self.path)
        if pin:
            return self._pin_model(pin.group(1))

        return self._send(404, {"error": "not_found"})

    def do_DELETE(self):
        if not self._authorized():
            return self._send(401, {"error": "unauthorized"})
        self.keyfile.refresh()

        match = re.fullmatch(r"/targets/([^/]+)", self.path)
        if not match:
            return self._send(404, {"error": "not_found"})
        if not self.keyfile.remove(match.group(1)):
            return self._send(404, {"error": "unknown_target"})
        self.keyfile.refresh()
        return self._send(200, {"ok": True})

    def _put_target(self):
        request = self._body()
        if request is None:
            return self._send(400, {"error": "bad_json"})

        provider = str(request.get("provider") or "").strip().lower()
        key = str(request.get("key") or "").strip()
        if not provider or not key:
            return self._send(400, {"error": "missing_fields"})

        entry = {"provider": provider, "key": key, "name": request.get("name") or provider}
        for passthrough in ("protocol", "base_url"):
            if request.get(passthrough):
                entry[passthrough] = request[passthrough]

        # The key is proved live before it's stored: a fresh listing, no cache.
        try:
            models = Target(entry).client().list_models(refresh=True).models
        except KeyCallError as error:
            return self._send(422, {"error": "refused", "message": str(error)})
        except Exception as error:
            return self._send(422, {"error": "refused", "message": str(error)})

        self.keyfile.upsert(entry)
        self.keyfile.refresh()
        return self._send(
            200,
            {
                "ok": True,
                "name": entry["name"],
                "provider": provider,
                "key_hint": key_hint(key),
                "models": [m.id for m in order_candidates(models)],
            },
        )

    def _pin_model(self, name):
        request = self._body()
        if request is None:
            return self._send(400, {"error": "bad_json"})

        target = self.keyfile.targets.get(name)
        if target is None:
            return self._send(404, {"error": "unknown_target"})

        model = str(request.get("model") or "").strip()
        if model:
            try:
                listed = target.models()
            except Exception as error:
                return self._send(422, {"error": "refused", "message": str(error)})
            if model not in listed:
                return self._send(422, {"error": "unknown_model"})

        self.keyfile.update_model(name, model)
        self.keyfile.refresh()
        return self._send(200, {"ok": True, "name": name, "model": model or None})

    def _generate(self):
        request = self._body()
        if request is None:
            return self._send(400, {"error": "bad_json"})

        prompt = request.get("prompt")
        if not prompt or not isinstance(prompt, str):
            return self._send(400, {"error": "missing_prompt"})

        name = request.get("target")
        if name:
            target = self.keyfile.targets.get(name)
        else:
            target = next(iter(self.keyfile.targets.values()), None)
        if target is None:
            return self._send(400, {"error": "unknown_target"})

        messages = []
        if request.get("system"):
            messages.append(Message(role="system", content=[TextInput(text=request["system"])]))
        messages.append(Message(role="user", content=[TextInput(text=prompt)]))

        kwargs = {"max_output_tokens": int(request.get("max_output_tokens", 400))}
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
                    if not (result.text or "").strip():
                        # Tokens were spent and nothing came back, most often a
                        # reasoning model that thought its way through the whole
                        # output budget. An empty answer is a failure for the
                        # caller, so the walk moves on.
                        last_error = RuntimeError(f"{model_id} returned no text")
                        result = None
                        continue
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keys", required=True, help="Path to the keys TOML")
    parser.add_argument("--port", type=int, default=4747)
    args = parser.parse_args()

    token = os.environ.get("QUORUM_SIDECAR_TOKEN")
    if not token:
        sys.exit("Set QUORUM_SIDECAR_TOKEN before starting; Quorum must hold the same value.")

    Handler.keyfile = KeyFile(args.keys)
    Handler.keyfile.refresh()
    Handler.token = token

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    names = ", ".join(Handler.keyfile.targets) or "none yet; add keys from Settings"
    print(f"Quorum sidecar on 127.0.0.1:{args.port}, targets: {names}")
    server.serve_forever()


if __name__ == "__main__":
    main()
