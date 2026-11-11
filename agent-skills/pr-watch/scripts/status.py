import datetime, json, os, sys

STATE = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "state")
REG = os.path.join(STATE, "prs.json")
PENDING = os.path.join(STATE, "pending.json")


def load(path, default):
    try:
        return json.load(open(path))
    except Exception:
        return default


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    json.dump(data, open(tmp, "w"), indent=2, sort_keys=True)
    os.replace(tmp, path)


def state_file(key):
    return os.path.join(STATE, ".pr-state", key.replace("/", "_").replace("#", "-") + ".json")


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


cmd = sys.argv[1]

if cmd == "table":
    prs = load(REG, {})
    if not prs:
        print("no PRs registered")
        sys.exit(0)
    pending = load(PENDING, {})
    print("%-46s %-8s %-9s %-10s %s" % ("PR", "state", "pending", "blocked", "worktree"))
    for key in sorted(prs):
        st = load(state_file(key), {})
        wt = prs[key].get("worktree") or "-"
        note = "" if not wt or wt == "-" or os.path.isdir(wt) else "  (MISSING)"
        print("%-46s %-8s %-9s %-10s %s%s" % (
            key, st.get("state") or "-",
            "yes" if st.get("pending") else "no",
            "yes" if st.get("blocked") else "no", wt, note))
    open_items = {k: v for k, v in pending.items() if not v.get("resolved")}
    if open_items:
        print("\nunresolved escalations:")
        for key, p in sorted(open_items.items()):
            print("  %-44s %s  %s" % (key, (p.get("at") or "")[:16], (p.get("note") or "")[:70]))

elif cmd == "handled":
    key = sys.argv[3]
    p = state_file(key)
    st = load(p, {})
    st["pending"] = False
    st.pop("blocked", None)
    st.pop("blockedNote", None)
    save(p, st)
    pend = load(PENDING, {})
    if key in pend:
        pend[key]["resolved"] = True
        pend[key]["resolvedAt"] = now()
        save(PENDING, pend)
    print("cleared: " + key)

elif cmd == "block":
    key, note = sys.argv[3], sys.argv[4]
    p = state_file(key)
    st = load(p, {})
    st["blocked"] = True
    st["blockedNote"] = note
    st["pending"] = False
    save(p, st)
    pend = load(PENDING, {})
    pend[key] = {"note": note, "at": now(), "resolved": False}
    save(PENDING, pend)
    print("blocked: %s — %s" % (key, note))
