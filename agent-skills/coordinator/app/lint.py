#!/usr/bin/env python3
"""Keep queue items greppable. Run before finishing any run that edits queue.json."""
import json, os, re, sys

LIMITS = {"title": 90, "why": 260, "ask": 140}

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "..", "state", "queue.json")
    if not os.path.exists(path):
        print("no queue.json yet — nothing to lint")
        return 0
    d = json.load(open(path))
    bad = 0
    for it in d["items"]:
        if it.get("kind") not in (None, "action", "decision", "start", "done", "blocked", "failed", "scope", "info"):
            print(f"{it['id']}: kind must be action, decision or start, got {it['kind']!r}")
            bad += 1
        if it["status"] != "open":
            continue
        for field, cap in LIMITS.items():
            text = it.get(field, "")
            if len(text) > cap:
                print(f"{it['id']}: {field} is {len(text)} chars, cap {cap}")
                bad += 1
            if field != "title":
                sentences = [s for s in re.split(r"(?<=[.!?])\s+", text.strip()) if s]
                if len(sentences) > 2:
                    print(f"{it['id']}: {field} has {len(sentences)} sentences, max 2")
                    bad += 1
    print("clean" if not bad else f"{bad} problem(s)")
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
