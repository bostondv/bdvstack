#!/usr/bin/env python3
"""Lint a draft against Boston's measured registers.

Usage: python3 check.py --register pr_description draft.md
Exit 1 when the draft clearly diverges.
"""
import argparse, re, sys, os, json

BANNED = ["leverage","utilize","facilitate","robust","delve","crucial","moreover",
          "furthermore","holistic","nuanced","myriad","plethora","additionally"]
HEDGES = ["i think","probably","maybe","seems","kind of","sort of","might","perhaps","possibly","likely"]
CUES = ["decide","decision","approve","choose","pick","confirm","your call","want me to",
        "should we","need you","let me know","next step","recommend","please"]
TARGET = {"pr_description":(9,15),"pr_comment":(9,16),"slack":(12,20),"doc":(10,16),"commit":(5,12)}
# measured p90 sentence length by register; failure is well past his own tail
LIMIT = {"pr_description":26,"pr_comment":27,"slack":27,"doc":30,"commit":20}

def sents(text):
    text = re.sub(r"(?m)^\s*- \[[ x]\].*$", "", text)
    t = re.sub(r"`[^`]*`","code",text)
    t = re.sub(r"(\d)\.(\d)", lambda m: m.group(1)+"\x00"+m.group(2), t)
    out = re.split(r"(?<=[.!?])\s+", t.replace("\n"," "))
    return [o.replace("\x00",".").strip() for o in out if o.strip()]

def paras(text):
    body = re.sub(r"^#+ .*$","",text,flags=re.M)
    return [p.strip() for p in re.split(r"\n\s*\n", body) if p.strip() and not p.strip().startswith(("|","```"))]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("draft")
    ap.add_argument("--register", default="pr_description", choices=list(TARGET))
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    text = open(a.draft).read()
    errs, warns = [], []
    ss = [s for p in paras(text) for s in sents(p)]
    lens = [len(s.split()) for s in ss]
    if lens:
        med = sorted(lens)[len(lens)//2]
        lo, hi = TARGET[a.register]
        if med > hi: warns.append(f"median sentence {med}w, {a.register} runs {lo}-{hi}w")
        for s in ss:
            n = len(s.split())
            if n > LIMIT[a.register] + 6: errs.append(f"{n}w sentence: {s[:80]}")
            elif n > 25: warns.append(f"{n}w sentence, past his p90 of {LIMIT[a.register]}")
    pp = [len(sents(p)) for p in paras(text)]
    for i, n in enumerate(pp):
        if n > 3: errs.append(f"paragraph {i+1} has {n} sentences")
    low = text.lower()
    for w in BANNED:
        n = len(re.findall(r"\b"+w+r"\b", low))
        if n: errs.append(f"banned word '{w}' x{n}")
    hedges = sum(low.count(h) for h in HEDGES)
    wc = len(re.findall(r"\S+", text)) or 1
    if a.register in ("pr_description","doc") and hedges*1000/wc > 6:
        warns.append(f"hedging {hedges*1000/wc:.1f}/1k; his {a.register} runs under 1")
    if a.register == "slack" and hedges == 0:
        warns.append("no hedging; his Slack runs 24/1k")
    run, pos = 0, None
    for s in ss:
        if "?" in s or any(c in s.lower() for c in CUES):
            pos = run + 1; break
        run += len(s.split())
    if pos is None: warns.append("no decision, question, or ask found")
    elif pos > wc * 0.35: errs.append(f"recommendation buried at word {pos} of {wc}")
    em = text.count("—")
    if em: warns.append(f"{em} em dash(es); his own writing has none")
    report = {"register": a.register, "words": wc, "median_sentence": sorted(lens)[len(lens)//2] if lens else 0,
              "first_actionable_word": pos, "em_dashes": em, "errors": errs, "warnings": warns}
    if a.json: print(json.dumps(report, indent=2))
    else:
        print(f"{a.register}: {wc} words, median sentence {report['median_sentence']}w, first ask at word {pos}")
        for e in errs: print("  FAIL", e)
        for w in warns: print("  warn", w)
        if not errs and not warns: print("  ok")
    sys.exit(1 if errs else 0)

if __name__ == "__main__":
    main()
