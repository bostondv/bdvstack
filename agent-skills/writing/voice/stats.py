#!/usr/bin/env python3
"""Register statistics for the voice corpus. Deterministic, stdlib only."""
import json, os, re, statistics as st

ROOT = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.join(ROOT, "corpus")

HEDGES = ["i think","probably","maybe","seems","might","kind of","sort of","tbh","afaik","imo",
          "fwiw","guessing","i don't know","not sure","likely","perhaps","roughly","i guess",
          "i'd guess","possibly","sort of","or so","approximately"]
CONTEXT_OPENERS = ["user report","we had","in order to","currently","today","this pr","the goal",
                   "on 2026","when ","we've been","previously","right now","at the moment"]
OUTCOME_OPENERS = ["adds","add","cut","cuts","fix","fixes","remove","removes","move","moves",
                   "replace","replaces","make","makes","ship","ships","enable","enables","bump","drops"]
FILLER = ["hey","so ","just ","wanted to","quick","circling","sorry","ok so","alright"]

def sents(text):
    text = re.sub(r"(?m)^\s*- \[[ x]\].*$", "", text)
    t = re.sub(r"`[^`]*`", "code", text)
    t = re.sub(r"(\d)\.(\d)", lambda m: m.group(1)+"\x00"+m.group(2), t)
    for a in ("e.g.","i.e.","vs.","etc."):
        t = t.replace(a, a.replace(".", "\x00"))
    parts = re.split(r"(?<=[.!?])\s+", t.replace("\n", " "))
    return [p.replace("\x00",".").strip() for p in parts if p.strip()]

def paras(text):
    body = re.sub(r"^#+ .*$", "", text, flags=re.M)
    return [p.strip() for p in re.split(r"\n\s*\n", body) if p.strip() and not p.strip().startswith(("|","```"))]

def analyse(path):
    raw = open(path).read()
    ss, ps = [], []
    for p in paras(raw):
        s = sents(p)
        if not s: continue
        ps.append(len(s)); ss += s
    words = re.findall(r"[A-Za-z0-9'’\-]+", raw)
    n = len(words) or 1
    lens = [len(s.split()) for s in ss]
    low = raw.lower()
    hedge = sum(low.count(h) for h in set(HEDGES))
    contractions = len(re.findall(r"\b\w+(?:'|’)(?:s|t|d|ll|re|ve|m)\b", raw))
    em = raw.count("—"); en = raw.count("–"); ddash = low.count("--")
    lower_start = len(re.findall(r"(?m)^[a-z]", raw))
    upper_start = len(re.findall(r"(?m)^[A-Z]", raw))
    first_sents = [sents(p)[0] for p in paras(raw) if sents(p)]
    ctx = sum(1 for s in first_sents if any(s.lower().startswith(c) or c in s.lower()[:60] for c in CONTEXT_OPENERS))
    out = sum(1 for s in first_sents if any(s.lower().lstrip("*#- ").startswith(o) for o in OUTCOME_OPENERS))
    fill = sum(1 for s in first_sents if any(s.lower().startswith(f) for f in FILLER))
    return {
        "words": len(words),
        "sentences": len(ss),
        "sentences_median": round(st.median(lens), 1) if lens else 0,
        "sentences_p90": sorted(lens)[int(len(lens)*0.9)-1] if lens else 0,
        "sentences_mean": round(sum(lens)/len(lens), 1) if lens else 0,
        "pct_over_25w": round(100*sum(1 for l in lens if l > 25)/len(lens), 1) if lens else 0,
        "pct_under_10w": round(100*sum(1 for l in lens if l < 10)/len(lens), 1) if lens else 0,
        "paragraphs": len(ps),
        "paras_median_sents": round(st.median(ps), 1) if ps else 0,
        "pct_paras_over_3": round(100*sum(1 for p in ps if p > 3)/len(ps), 1) if ps else 0,
        "hedges_per_1k": round(1000*hedge/n, 1),
        "contractions_per_1k": round(1000*contractions/n, 1),
        "em_dash_per_1k": round(1000*em/n, 2),
        "en_dash_per_1k": round(1000*en/n, 2),
        "double_hyphen": ddash,
        "lowercase_line_start_pct": round(100*lower_start/max(1, lower_start+upper_start), 1),
        "opener_context_pct": round(100*ctx/len(first_sents), 1) if first_sents else 0,
        "opener_outcome_pct": round(100*out/len(first_sents), 1) if first_sents else 0,
        "opener_filler_pct": round(100*fill/len(first_sents), 1) if first_sents else 0,
    }

out = {os.path.basename(f): analyse(os.path.join(CORPUS, f)) for f in sorted(os.listdir(CORPUS)) if f.endswith(".md")}
json.dump(out, open(os.path.join(ROOT, "stats.json"), "w"), indent=2)
cols = ["words","sentences_median","sentences_p90","pct_over_25w","pct_under_10w","paras_median_sents","pct_paras_over_3","hedges_per_1k","contractions_per_1k","em_dash_per_1k","lowercase_line_start_pct","opener_context_pct","opener_outcome_pct","opener_filler_pct"]
print(f"{'register':26}" + "".join(f"{c[:9]:>11}" for c in cols))
for k, v in out.items():
    print(f"{k:26}" + "".join(f"{v[c]:>11}" for c in cols))
