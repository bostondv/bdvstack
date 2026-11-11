#!/usr/bin/env python3
"""Tiny queue server for the coordinator loop. No deps.

  python3 serve.py            -> http://localhost:8787
  GET  /            the app
  GET  /queue       queue.json
  POST /resolve     {id, note?}   mark done
  POST /snooze      {id, until?}  push out
  POST /reopen      {id}
  POST /add         {item...}     append a queue item
  POST /update      {id, ...}     patch fields on one item
  POST /start       {id}          authorise a start item; writes the ledger line
  POST /writes      {who, action, id, url?, why?}  prepend one WRITES.md line
  POST /notify      {from, kind, id?, title?, link?, note?}  a session reporting in
  GET  /prs         the PR watchdog registry
  POST /prs         {pr, thread, automation?, worktree?, branch?}  register a PR
  POST /prs/unregister  {pr}      watchdog is done
  POST /prs/touch   {pr, attempts?, lastActivity?}  a tick happened

Every write goes through this process and the module lock, so two leads
posting at once can't clobber each other's read-modify-write.
  GET  /writes      WRITES.md parsed to json
  GET  /ledger      LEDGER.md as one line per entry, newest first
  GET  /activity    WRITES.md + LEDGER.md merged, newest first
  GET  /events      server-sent events; one `changed` per queue.json write
"""
import datetime, json, os, re, sys, threading, time
from zoneinfo import ZoneInfo
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP = os.path.dirname(os.path.abspath(__file__))     # .../coordinator/app
ROOT = os.path.dirname(APP)                          # .../coordinator
STATE = os.path.join(ROOT, "state")
QUEUE = os.path.join(STATE, "queue.json")
DECISIONS = os.path.join(STATE, "decisions.json")
LEDGER = os.path.join(STATE, "LEDGER.md")
WRITES = os.path.join(STATE, "WRITES.md")
NOTICES = os.path.join(STATE, "NOTICES.md")
PRS = os.path.join(STATE, "prs.json")
LOCK = threading.Lock()
PORT = int(os.environ.get("PORT", "8787"))

LOCAL_TZ = ZoneInfo("America/Toronto")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
KINDS = ("action", "decision", "start")
NOTICE_KINDS = ("done", "blocked", "failed", "scope", "info")
DEDUPE_SECONDS = 600
POST_ONLY = ("/notify", "/add", "/update", "/start", "/writes", "/decide",
             "/resolve", "/snooze", "/reopen", "/prs", "/prs/unregister", "/prs/touch")
STATUSES = ("open", "snoozed", "done", "decided", "started")


def now_local():
    return datetime.datetime.now(LOCAL_TZ)


def stamp():
    """Local wall clock on every line we write, so relative times are real."""
    return now_local().strftime("%Y-%m-%d %H:%M")


def stamp_iso():
    """Full ISO with offset, for decisions.json."""
    return now_local().isoformat(timespec="seconds")


def write_text(path, text):
    """Atomic write. Files sit read-only at rest so a stray `>>` fails loudly."""
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)
    try:
        os.chmod(path, 0o444)
    except OSError:
        pass


def load():
    with open(QUEUE) as f:
        return json.load(f)


def save(data):
    write_text(QUEUE, json.dumps(data, indent=2))


# One line per write: `- **date** — who · action · id · why`.
# Anything that isn't that shape (headings, prose) is skipped, not published.
_WRITE_LINE = re.compile(r"^-\s*\*\*(.+?)\*\*\s*[\u2014\u2013-]\s*(.+)$")
_MD_LINK = re.compile(r"^\[([^\]]+)\]\(([^)]+)\)")
_PLAIN_ID = re.compile(r"^[A-Z][A-Z0-9]*(?:[-_][A-Z0-9]+)*-\d+\b")
_STAMPED = re.compile(r"^-\s*\*\*\d{4}-\d{2}-\d{2} \d{2}:\d{2}\*\*")


def parse_writes(path=None):
    try:
        with open(path or WRITES, encoding="utf-8") as f:
            raw = f.read()
    except FileNotFoundError:
        return []
    out = []
    for line in raw.splitlines():
        m = _WRITE_LINE.match(line.strip())
        if not m:
            continue
        at = m.group(1).strip()
        parts = [p.strip() for p in m.group(2).split("\u00b7")]
        if len(parts) < 2:
            continue
        who, action = parts[0], parts[1]
        ident = url = ""
        tail = parts[2:]
        if tail:
            head = tail[0]
            lm = _MD_LINK.match(head)
            if lm:
                ident, url = lm.group(1), lm.group(2)
                head = head[lm.end():].lstrip(" ,;-\u2013\u2014")
            else:
                pm = _PLAIN_ID.match(head)
                if pm:
                    ident = pm.group(0)
                    head = head[pm.end():].lstrip(" ,;-\u2013\u2014")
            tail = ([head] if head else []) + tail[1:]
        why = " \u00b7 ".join(t for t in tail if t)
        why = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", why)
        out.append({"date": at, "at": at, "has_time": " " in at,
                    "who": who, "action": action,
                    "id": ident, "url": url, "why": why.strip(" \u00b7")})
    out.sort(key=lambda e: e["date"], reverse=True)
    return out


def patch(item_id, status, note=None):
    with LOCK:
        data = load()
        for it in data["items"]:
            if it["id"] == item_id:
                it["status"] = status
                it[status + "At"] = stamp_iso()
                if note:
                    it.setdefault("log", []).append(note)
                break
        save(data)
        return data


def prepend_entry(path, line, header="# Written log\n\nNewest at top.\n"):
    """Put a line at the top of a markdown log, leaving every existing line alone."""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        text = ""
    if not text.strip():
        text = header
    marker = "\n- **"
    i = text.find(marker)
    if i == -1:
        text = text.rstrip("\n") + "\n\n" + line
    else:
        text = text[: i + 1] + line + text[i + 1 :]
    write_text(path, text)


def ledger_append(item, choice, note=None):
    import datetime
    line = f"- **{stamp()}** — {item['area']}: {item['title']} → **{choice}**"
    if note:
        line += f". {note}"
    line += "\n"
    prepend_entry(LEDGER, line)


NOTICE_TO_ITEM = {"done": "action", "failed": "action",
                  "blocked": "decision", "scope": "decision"}


def _norm_kind(raw):
    """Accept what agents naturally send; store what the page understands."""
    kind = (raw.get("kind") or "").strip().lower() if isinstance(raw, dict) else ""
    if not kind:
        return None, None
    if kind in KINDS:
        return kind, None
    if kind == "info":
        return "info", None
    if kind in NOTICE_TO_ITEM:
        return NOTICE_TO_ITEM[kind], kind
    return None, None


def _clean(raw):
    if not isinstance(raw, dict):
        return {}
    out = {}
    for k in ("id", "area", "title", "source", "why", "ask"):
        v = raw.get(k)
        if isinstance(v, str):
            out[k] = v.strip()
    v = raw.get("options")
    if isinstance(v, list) and v and all(o.__class__ is str for o in v):
        out["options"] = [o.strip() for o in v]
    v = raw.get("links")
    if isinstance(v, list):
        out["links"] = [l for l in v if isinstance(l, dict) and l.get("url")]
    v = raw.get("priority")
    if isinstance(v, int) and not isinstance(v, bool):
        out["priority"] = v
    v = raw.get("kind")
    if isinstance(v, str):
        out["kind"] = v.strip()
    v = raw.get("status")
    if isinstance(v, str):
        out["status"] = v.strip()
    v = raw.get("since")
    if isinstance(v, str) and v.strip():
        try:
            datetime.datetime.fromisoformat(v.strip().replace("Z", "+00:00"))
            out["since"] = v.strip()
        except ValueError:
            pass          # caller gets a 400 below
    return out


def _bad_since(raw):
    v = raw.get("since") if isinstance(raw, dict) else None
    if not isinstance(v, str) or not v.strip():
        return False
    try:
        datetime.datetime.fromisoformat(v.strip().replace("Z", "+00:00"))
        return False
    except ValueError:
        return True


def add_item(raw):
    item = _clean(raw)
    if not item.get("id") or not item.get("area") or not item.get("title"):
        return None, "id, area and title are required"
    if not ID_RE.match(item["id"]):
        return None, "id must be a lowercase slug"
    if _bad_since(raw):
        return None, "since must be an ISO timestamp, not prose"
    item["createdAt"] = stamp_iso()
    raw_kind = (raw.get("kind") or "").strip().lower()
    mapped, original = _norm_kind(raw)
    if raw_kind and mapped is None:
        return None, "kind must be one of " + ", ".join(KINDS + NOTICE_KINDS)
    if mapped == "info":
        return None, "info never becomes an item; POST it to /notify"
    item["kind"] = mapped or "decision"
    if original:
        item.setdefault("notice", {})["kind"] = original
    item.setdefault("priority", 2)
    item.pop("status", None)
    item["status"] = "open"
    with LOCK:
        data = load()
        if any(i.get("id") == item["id"] for i in data["items"]):
            return None, "id already exists: " + item["id"]
        data["items"].append(item)
        save(data)
    return item, None


def update_item(item_id, raw):
    fields = _clean(raw)
    fields.pop("id", None)
    fields.pop("createdAt", None)
    if _bad_since(raw):
        return None, "since must be an ISO timestamp, not prose"
    if "kind" in fields:
        mapped, original = _norm_kind(fields)
        if mapped is None or mapped == "info":
            return None, "kind must be one of " + ", ".join(KINDS + NOTICE_KINDS)
        fields["kind"] = mapped
        if original:
            fields.setdefault("notice", {})["kind"] = original
    if isinstance(fields.get("status"), str) and fields["status"] not in STATUSES:
        return None, "unknown status"
    with LOCK:
        data = load()
        item = next((i for i in data["items"] if i.get("id") == item_id), None)
        if not item:
            return None, "no such item: %s" % item_id
        item.update(fields)
        save(data)
    return item, None


def append_write(raw):
    if not isinstance(raw, dict):
        return None, "body must be an object"
    line = (raw.get("line") or "").strip()
    if line:
        if not _STAMPED.match(line):
            return None, "line must look like '- **YYYY-MM-DD HH:MM** — who · action · …'"
    else:
        import datetime
        who = (raw.get("who") or "").strip()
        action = (raw.get("action") or "").strip()
        ident = (raw.get("id") or "").strip()
        url = (raw.get("url") or "").strip()
        why = (raw.get("why") or "").strip()
        date = (raw.get("date") or stamp()).strip()
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}", date):
            return None, "date must be 'YYYY-MM-DD HH:MM', not date-only"
        if not who or not action or not (ident or why):
            return None, "who, action and one of id/why are required"
        parts = ["- **%s** \u2014 %s" % (date, who), action]
        if ident:
            parts.append("[%s](%s)" % (ident, url) if url else ident)
        if why:
            parts.append(why)
        line = " \u00b7 ".join(parts)
    with LOCK:
        prepend_entry(WRITES, line + "\n")
    return {"line": line}, None


def activity():
    rows = []
    for e in parse_writes():
        rows.append({"at": e["at"], "has_time": e["has_time"], "who": e["who"],
                     "action": e["action"], "target": e["id"], "url": e["url"],
                     "text": e["why"], "source": "writes"})
    for e in parse_writes(NOTICES):
        rows.append({"at": e["at"], "has_time": e["has_time"], "who": e["who"],
                     "action": e["action"], "target": e["id"], "url": e["url"],
                     "text": e["why"], "source": "notice"})
    for e in parse_ledger():
        rows.append({"at": e["at"], "has_time": e["has_time"], "who": "", "action": "",
                     "target": "", "url": "", "text": e["text"], "source": "ledger"})
    rows.sort(key=lambda r: r["at"], reverse=True)
    return rows[:200]


def load_prs():
    try:
        with open(PRS, encoding="utf-8") as f:
            data = json.load(f)
    except (FileNotFoundError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def save_prs(data):
    write_text(PRS, json.dumps(data, indent=2, sort_keys=True))


def _pr_key(raw):
    key = (raw.get("key") or "").strip()
    if key and "#" in key:
        return key
    repo = (raw.get("repo") or "").strip()
    pr = str(raw.get("pr") or "").strip().lstrip("#")
    return "%s#%s" % (repo, pr) if repo and pr else ""


def register_pr(raw):
    repo = (raw.get("repo") or "").strip()
    pr = str(raw.get("pr") or "").strip().lstrip("#")
    if not repo or "/" not in repo:
        return None, "repo is required, as owner/name"
    if not pr.isdigit():
        return None, "pr must be the numeric pull request id"
    thread = (raw.get("thread") or "").strip()
    if not thread:
        return None, "thread is required"
    key = "%s#%s" % (repo, pr)
    with LOCK:
        data = load_prs()
        now = stamp_iso()
        entry = data.get(key, {})
        entry.update({
            "repo": repo,
            "pr": pr,
            "thread": thread,
            "automation": (raw.get("automation") or "").strip()
                          or entry.get("automation")
                          or "pr-watch-%s-%s" % (repo.split("/")[-1], pr),
            "pipeline": (raw.get("pipeline") or "").strip() or entry.get("pipeline", ""),
            "worktree": (raw.get("worktree") or "").strip() or entry.get("worktree", ""),
            "branch": (raw.get("branch") or "").strip() or entry.get("branch", ""),
            "created": entry.get("created") or now,
            "lastActivity": now,
        })
        entry.setdefault("attempts", {})
        data[key] = entry
        save_prs(data)
    return {"key": key, **entry}, None


def unregister_pr(raw):
    key = _pr_key(raw)
    if not key:
        return None, "key or repo+pr is required"
    with LOCK:
        data = load_prs()
        existed = data.pop(key, None) is not None
        save_prs(data)
    return {"key": key, "removed": existed, "remaining": len(data)}, None


def touch_pr(raw):
    key = _pr_key(raw)
    if not key:
        return None, "key or repo+pr is required"
    with LOCK:
        data = load_prs()
        entry = data.get(key)
        if not entry:
            return None, "not registered: %s" % key
        entry["lastActivity"] = (raw.get("lastActivity") or "").strip() or stamp_iso()
        attempts = raw.get("attempts")
        if isinstance(attempts, dict):
            entry["attempts"] = {k: v for k, v in attempts.items() if isinstance(v, list)}
        seen = raw.get("lastSeen")
        if isinstance(seen, str) and seen.strip():
            entry["lastSeen"] = seen.strip()
        cursors = raw.get("cursors")
        if isinstance(cursors, dict):
            entry["cursors"] = cursors
        if "pending" in raw:
            entry["pending"] = bool(raw.get("pending"))
        save_prs(data)
    return {"key": key, **entry}, None


def _slug(text):
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", text.lower())).strip("-")


def _notice_seen(frm, ident, action, seconds=DEDUPE_SECONDS):
    now = now_local().replace(tzinfo=None)
    for e in parse_writes(NOTICES):
        if not e["has_time"] or e["who"] != frm or e["id"] != ident or e["action"] != action:
            continue
        try:
            when = datetime.datetime.strptime(e["at"], "%Y-%m-%d %H:%M")
        except ValueError:
            continue
        if (now - when).total_seconds() <= seconds:
            return True
    return False


def _area_for(frm, ident):
    hint = (frm + " " + ident).lower()
    return "Extensibility" if "ext" in hint else "Web Platform"


def notify(raw):
    if not isinstance(raw, dict):
        return None, "body must be an object"
    frm = (raw.get("from") or "").strip()
    kind = (raw.get("kind") or "").strip().lower()
    ident = (raw.get("id") or "").strip()
    title = (raw.get("title") or "").strip()
    link = (raw.get("link") or "").strip()
    note = (raw.get("note") or "").strip()
    if not frm:
        return None, "from is required"
    if kind not in NOTICE_KINDS:
        return None, "kind must be one of " + ", ".join(NOTICE_KINDS)
    if kind != "info" and not ident:
        return None, "id is required for kind=%s" % kind

    action = kind.upper()
    line = "- **%s** \u2014 %s \u00b7 %s" % (stamp(), frm, action)
    if ident:
        line += " \u00b7 " + ("[%s](%s)" % (ident, link) if link else ident)
    if note:
        line += " \u00b7 " + note.replace("\n", " ")

    with LOCK:
        if _notice_seen(frm, ident, action):
            return {"ok": True, "ignored": True, "reason": "duplicate within 10 minutes"}, None
        prepend_entry(NOTICES, line + "\n",
                      header="# Notices\n\nOne line per agent report. Newest at top.\n")
        if kind == "info":
            return {"ok": True, "ignored": False, "item": None}, None

        data = load()

        prefix = {"done": "Review", "failed": "Failed", "blocked": "Blocked", "scope": "Scope"}[kind]
        head = "%s: %s" % (prefix, ident)
        if title:
            head = "%s %s" % (head, title)
        head = head[:90]

        base = _slug("notice-%s-%s-%s" % (frm, ident, kind))
        existing = {i.get("id") for i in data["items"]}
        item_id, n = base, 2
        while item_id in existing:
            item_id = "%s-%d" % (base, n)
            n += 1

        item = {
            "id": item_id,
            "area": (raw.get("area") or "").strip() or _area_for(frm, ident),
            "kind": "action" if kind in ("done", "failed") else "decision",
            "priority": 0 if kind == "failed" else 1,
            "status": "open",
            "title": head,
            "source": frm,
            "why": (note or title)[:260],
            "createdAt": stamp_iso(),
            "notice": {"from": frm, "kind": kind, "id": ident, "note": note},
        }
        if link:
            item["links"] = [{"label": ident, "url": link}]
        data["items"].append(item)
        save(data)
        return {"ok": True, "ignored": False, "item": item_id}, None


def start_item(item_id, started_by=""):
    import datetime
    today = datetime.date.today().isoformat()
    with LOCK:
        data = load()
        item = next((i for i in data["items"] if i.get("id") == item_id), None)
        if not item:
            return None, "no such item: %s" % item_id
        if item.get("kind", "decision") != "start":
            return None, "not a start item"
        if item.get("status") != "open":
            return None, "item is %s" % item.get("status")
        # the ledger line is the authorisation, so it lands first
        prepend_entry(LEDGER, "- **%s** \u2014 START \u2014 %s \u2014 %s\n"
                      % (stamp(), item["id"], item["title"]))
        item["status"] = "started"
        item["startedAt"] = stamp_iso()
        # only ever record a name someone actually gave us
        item["startedBy"] = (started_by or item.get("startedBy") or "").strip()
        save(data)
    return item, None


def decide(item_id, choice, note=None):
    with LOCK:
        data = load()
        item = next((i for i in data["items"] if i["id"] == item_id), None)
        if not item:
            return data
        import datetime
        item["status"] = "decided"
        item["decision"] = {"choice": choice, "note": note, "at": stamp_iso()}
        save(data)
        ledger_append(item, choice, note)
        try:
            with open(DECISIONS) as f:
                hist = json.load(f)
        except Exception:
            hist = []
        hist.append({"id": item_id, "area": item["area"], "title": item["title"],
                     "choice": choice, "note": note, "at": item["decision"]["at"]})
        write_text(DECISIONS, json.dumps(hist, indent=2))
        return data


LEDGER_LINE = re.compile(r"^-\s*\*\*(.+?)\*\*\s*[\u2014\u2013-]\s*(.+)$")


def parse_ledger():
    """One line per entry, in file order. No interpretation."""
    try:
        with open(LEDGER, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        return []
    out = []
    for raw in lines:
        m = LEDGER_LINE.match(raw.strip())
        if m:
            at = m.group(1).strip()
            text = m.group(2).strip().replace("**", "")   # bold markers only, no semantics
            out.append({"date": at, "at": at, "has_time": " " in at, "text": text})
    return out


def queue_mtime():
    """Fingerprint of everything the board renders, so any write pushes an event."""
    out = []
    for path in (QUEUE, LEDGER, WRITES, NOTICES, PRS):
        try:
            out.append(os.stat(path).st_mtime_ns)
        except OSError:
            out.append(None)
    return tuple(out)


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def _send(self, code, body=b"", ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


    def stream_events(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()
        last = queue_mtime()
        beat = time.time()
        try:
            self.wfile.write(b": connected\n\n")
            self.wfile.flush()
            while True:
                time.sleep(1)
                current = queue_mtime()
                if current != last:
                    last = current
                    self.wfile.write(b"event: changed\ndata: queue\n\n")
                    self.wfile.flush()
                if time.time() - beat >= 20:
                    beat = time.time()
                    self.wfile.write(b": ping\n\n")
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            self.close_connection = True

    def do_GET(self):
        self.path = self.path.rstrip("/") or "/"
        if self.path in ("/", "/index.html"):
            with open(os.path.join(APP, "index.html"), "rb") as f:
                return self._send(200, f.read(), "text/html; charset=utf-8")
        if self.path.rstrip("/") in POST_ONLY and self.path.rstrip("/") != "/prs":
            return self._send(405, json.dumps({
                "error": "use POST", "path": self.path.rstrip("/"),
                "example": "curl -X POST -H 'Content-Type: application/json' -d '{...}' "
                           "http://localhost:%d%s" % (PORT, self.path.rstrip("/"))
            }).encode())
        if self.path == "/events":
            return self.stream_events()
        if self.path == "/queue":
            with open(QUEUE, "rb") as f:
                return self._send(200, f.read())
        if self.path == "/prs":
            try:
                data = load_prs()
            except Exception:
                data = {}
            return self._send(200, json.dumps({"count": len(data), "prs": data}).encode())
        if self.path == "/activity":
            try:
                rows = activity()
            except Exception:
                rows = []
            return self._send(200, json.dumps({"count": len(rows), "entries": rows}).encode())
        if self.path == "/ledger":
            try:
                entries = parse_ledger()
            except Exception:
                entries = []
            return self._send(200, json.dumps({"count": len(entries), "entries": entries}).encode())
        if self.path == "/writes":
            try:
                entries = parse_writes()
            except Exception:
                entries = []
            body = json.dumps({"count": len(entries), "entries": entries,
                               "missing": not os.path.exists(WRITES)}).encode()
            return self._send(200, body)
        self._send(404, json.dumps({
            "error": "not found", "path": self.path,
            "get": ["/", "/queue", "/activity", "/ledger", "/writes", "/prs", "/events"],
            "post": sorted(POST_ONLY),
        }).encode())

    def do_POST(self):
        self.path = self.path.rstrip("/") or "/"
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n) or b"{}")
        ident = body.get("id")
        if self.path in ("/prs", "/prs/unregister", "/prs/touch"):
            if self.path == "/prs":
                payload, err = register_pr(body)
            elif self.path == "/prs/unregister":
                payload, err = unregister_pr(body)
            else:
                payload, err = touch_pr(body)
            if err:
                return self._send(400, json.dumps({"error": err}).encode())
            return self._send(200, json.dumps(payload).encode())
        if self.path == "/notify":
            payload, err = notify(body)
            if err:
                return self._send(400, json.dumps({"error": err}).encode())
            return self._send(200, json.dumps(payload).encode())
        if self.path in ("/add", "/update", "/start", "/writes"):
            if self.path == "/add":
                payload, err = add_item(body)
            elif self.path == "/update":
                payload, err = update_item(ident, body)
            elif self.path == "/start":
                payload, err = start_item(ident, (body.get("startedBy") or ""))
            else:
                payload, err = append_write(body)
            if err:
                return self._send(400, json.dumps({"error": err}).encode())
            return self._send(200, json.dumps(payload).encode())
        if self.path == "/decide":
            self._send(200, json.dumps(decide(ident, body.get("choice"), body.get("note"))).encode())
        elif self.path == "/resolve":
            self._send(200, json.dumps(patch(ident, "done", body.get("note"))).encode())
        elif self.path == "/snooze":
            self._send(200, json.dumps(patch(ident, "snoozed", body.get("note"))).encode())
        elif self.path == "/reopen":
            self._send(200, json.dumps(patch(ident, "open", body.get("note"))).encode())
        else:
            self._send(404, json.dumps({
                "error": "not found", "path": self.path,
                "post": sorted(POST_ONLY),
            }).encode())

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    for _p in (QUEUE, LEDGER, WRITES, DECISIONS):
        try:
            os.chmod(_p, 0o444)
        except OSError:
            pass
    print(f"queue -> http://localhost:{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
