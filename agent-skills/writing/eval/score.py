#!/usr/bin/env python3
"""Deterministic scoring for writing-rule changes. No model, no dependencies.

Usage:
  python3 score.py dir <dir>              # JSON metrics for every *.md in dir
  python3 score.py run <version>          # score fixtures + rewrites/<version>, print table, write runs/
"""
import json, os, re, sys, glob, datetime

ABBREV = ("e.g.", "i.e.", "vs.", "etc.", "no.", "fig.", "al.", "cf.", "approx.")
ACTION_CUES = (
    "decide", "decision", "approve", "sign off", "choose", "pick", "confirm",
    "your call", "want me to", "should we", "need you", "let me know",
    "next step", "action", "recommend", "i'd suggest", "please",
)
BOX_CHARS = set("┌┐└┘├┤┬┴┼│─╔╗╚╝║═╠╣╦╩╬")

def strip_code(text):
    """Return (prose, blocks) where blocks are fenced code contents."""
    blocks, out = [], []
    in_fence = False
    buf, lang = [], ""
    for line in text.split("\n"):
        if line.strip().startswith("```"):
            if in_fence:
                blocks.append((lang, "\n".join(buf))); buf = []
            else:
                lang = line.strip().strip("`").strip().lower()
            in_fence = not in_fence
            continue
        (buf if in_fence else out).append(line)
    if buf:
        blocks.append((lang, "\n".join(buf)))
    return "\n".join(out), blocks

def prose_text(md):
    t = md
    t = re.sub(r"^\s*#+ .*$", "", t, flags=re.M)            # headings
    t = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", t)               # images
    t = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", t)           # links -> text
    t = re.sub(r"<[^>]+>", "", t)                            # html tags
    t = re.sub(r"`[^`]*`", " code ", t)                      # inline code
    t = re.sub(r"^\s*\|.*$", "", t, flags=re.M)              # table rows
    t = re.sub(r"^\s*[-*+]\s+", "", t, flags=re.M)           # bullets
    t = re.sub(r"^\s*\d+\.\s+", "", t, flags=re.M)           # numbered
    t = re.sub(r"^\s*>\s?", "", t, flags=re.M)               # quotes
    return t

def paragraphs(md):
    """Prose paragraphs only: fenced blocks, tables, lists and quotes are excluded."""
    prose, _ = strip_code(md)
    blocks = [b.strip() for b in re.split(r"\n\s*\n", prose) if b.strip()]
    out = []
    for b in blocks:
        if re.match(r"^\s*([-*+]|\d+\.|\||>)", b):
            continue
        b = re.sub(r"^\s*#+ .*$", "", b, flags=re.M)
        b = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", b)
        b = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", b)
        b = re.sub(r"`[^`]*`", " code ", b)
        if b.strip():
            out.append(b.strip())
    return out

def sentences(para):
    s = para
    for a in ABBREV:
        s = s.replace(a, a.replace(".", "\x00"))
    s = re.sub(r"(\d)\.(\d)", lambda m: m.group(1) + "\x00" + m.group(2), s)
    parts = re.split(r"(?<=[.!?])\s+", s)
    return [p.replace("\x00", ".").strip() for p in parts if p.strip()]

def syllables(word):
    w = re.sub(r"[^a-z]", "", word.lower())
    if not w:
        return 1
    groups = re.findall(r"[aeiouy]+", w)
    n = len(groups)
    if w.endswith("e") and not w.endswith(("le", "ee")) and n > 1:
        n -= 1
    return max(1, n)

def readability(words, sents, raw_sentences):
    if not words or not sents:
        return {}
    asl = len(words) / sents
    syl = sum(syllables(w) for w in words)
    asw = syl / len(words)
    poly = sum(1 for w in words if syllables(w) >= 3)
    chars = sum(len(w) for w in words)
    flesch = round(206.835 - 1.015 * asl - 84.6 * asw, 1)
    return {
        "flesch": flesch,
        "fk_grade": round(0.39 * asl + 11.8 * asw - 15.59, 1),
        "fog": round(0.4 * (asl + 100 * poly / len(words)), 1),
        "smog": round(1.0430 * (30 * poly / sents) ** 0.5 + 3.1291, 1),
        "ari": round(4.71 * (chars / len(words)) + 0.5 * asl - 21.43, 1),
        "coleman_liau": round(0.0588 * (chars / len(words) * 100) - 0.296 * (sents / len(words) * 100) - 15.8, 1),
        "polysyllable_pct": round(100 * poly / len(words), 1),
        "chars_per_word": round(chars / len(words), 2),
    }

def flesch(words, sents):
    if not words or not sents:
        return 0.0
    syl = sum(syllables(w) for w in words)
    return round(206.835 - 1.015 * (len(words) / sents) - 84.6 * (syl / len(words)), 1)

def ascii_art(blocks):
    n = 0
    for lang, b in blocks:
        if lang in ("mermaid", "diff"):
            continue
        lines = b.split("\n")
        boxed = sum(1 for ln in lines if sum(ch in BOX_CHARS for ch in ln) >= 2)
        framed = sum(1 for ln in lines if re.match(r"^\s*[+|][-+=]{3,}", ln))
        arrows = len(re.findall(r"(-->|<-|=>|->)", b))
        if boxed >= 2 or framed >= 2 or arrows >= 3:
            n += 1
    return n

def score(md, name=""):
    prose, blocks = strip_code(md)
    paras = paragraphs(md)
    per_para = [len(sentences(p)) for p in paras]
    # sentences come from all prose (list items included); paragraphs are prose blocks only
    all_sents = sentences(prose_text(prose))
    words = re.findall(r"[A-Za-z0-9'’\-]+", prose_text(prose))
    # first actionable sentence
    pos, idx = None, None
    running = 0
    for i, s in enumerate(all_sents):
        low = s.lower()
        if "?" in low or any(c in low for c in ACTION_CUES):
            pos, idx = running + 1, i + 1
            break
        running += len(s.split())
    longest = max((len(s.split()) for s in all_sents), default=0)
    tables = len(re.findall(r"^\s*\|.*\|\s*$\n^\s*\|?[\s:|-]+\|?\s*$", md, flags=re.M))
    figures = (len(re.findall(r"!\[[^\]]*\]\(", md)) + sum(1 for lang, _ in blocks if lang == "mermaid")
               + len(re.findall(r"<(figure|div|svg)", md, flags=re.I)))
    return {
        "words": len(words),
        "sentences": len(all_sents),
        "paragraphs": len(paras),
        "longest_sentence": longest,
        "mean_words_per_sentence": round(len(words) / len(all_sents), 1) if all_sents else 0,
        "max_sentences_per_paragraph": max(per_para, default=0),
        "tables": tables,
        "figures": figures,
        "em_dashes": md.count("—"),
        "unlinked_refs": len(re.findall(r"(?:[A-Z]{2,6}-\d{1,5}|#\d{4,6})",
                                        re.sub(r"\[[^\]]*\]\([^)]*\)", "", md))),
        "pr_template_pct": (lambda h: round(100 * sum(1 for r in ("why", "what") if r in h) / 2))( 
            {m.group(1).strip().lower() for m in re.finditer(r"(?m)^#{1,3}\s+(.+)$", md)}) if name.startswith("pr-") else None,
        "ascii_art_blocks": ascii_art(blocks),
        **readability(words, len(all_sents), all_sents),
        "first_actionable_word": pos,
        "first_actionable_sentence": idx,
        "questions": sum(1 for s in all_sents if "?" in s),
    }

def score_dir(d):
    out = {}
    for f in sorted(glob.glob(os.path.join(d, "*.md"))):
        out[os.path.basename(f)] = score(open(f).read(), os.path.basename(f))
    return out

def agg(docs):
    keys = [k for k in next(iter(docs.values())).keys()]
    out = {}
    for k in keys:
        vals = [d[k] for d in docs.values() if d.get(k) is not None]
        out[k] = round(sum(vals) / len(vals), 1) if vals else 0
    return out

METRICS = [
    ("words", "words", "lower"),
    ("longest_sentence", "longest sentence (words)", "lower"),
    ("max_sentences_per_paragraph", "max sentences / paragraph", "lower"),
    ("tables", "tables", "higher"),
    ("figures", "figures", "higher"),
    ("first_actionable_word", "first actionable word", "lower"),
    ("em_dashes", "em dashes", "either"),
    ("ascii_art_blocks", "ASCII/box diagrams", "lower"),
    ("pr_template_pct", "PR template headings %", "higher"),
    ("flesch", "Flesch reading ease", "higher"),
]

def run(version):
    root = os.path.dirname(os.path.abspath(__file__))
    before = score_dir(os.path.join(root, "fixtures"))
    after_dir = os.path.join(root, "rewrites", version)
    if not os.path.isdir(after_dir):
        sys.exit(f"no rewrites at {after_dir}; write them under that directory first")
    after = score_dir(after_dir)
    missing = set(before) - set(after)
    if missing:
        sys.exit(f"rewrites missing for: {', '.join(sorted(missing))}")
    a, b = agg(before), agg(after)
    os.makedirs(os.path.join(root, "runs"), exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y%m%dT%H%M%S")
    prev = sorted(glob.glob(os.path.join(root, "runs", f"*-{version}.json")))
    runpath = os.path.join(root, "runs", f"{ts}-{version}.json")
    json.dump({"version": version, "timestamp": ts, "fixtures": before, "rewrites": after,
               "aggregate": {"before": a, "after": b}}, open(runpath, "w"), indent=2)

    prev_agg = None
    if prev:
        try:
            prev_agg = json.load(open(prev[-1]))["aggregate"]["after"]
        except (KeyError, ValueError):
            prev_agg = None

    print(f"\nwriting rules {version} — {len(before)} fixtures — {ts}")
    print(f"{'metric':34} {'before':>8} {'after':>8} {'delta':>8}  {'vs prev':>8}")
    for key, label, direction in METRICS:
        bv, av = a.get(key, 0), b.get(key, 0)
        d = av - bv
        pv = "" if prev_agg is None else f"{av - prev_agg.get(key, 0):+.1f}"
        print(f"{label:34} {bv:>8.1f} {av:>8.1f} {d:>+8.1f}  {pv:>8}")
    print(f"\nwrote {os.path.relpath(runpath)}")

def compare(versions):
    root = os.path.dirname(os.path.abspath(__file__))
    base = agg(score_dir(os.path.join(root, "fixtures")))
    cols = {"baseline": base}
    for v in versions:
        cols[v] = agg(score_dir(os.path.join(root, "rewrites", v)))
    head = f"{'metric':30}" + "".join(f"{k:>10}" for k in cols)
    print("\n" + head)
    for key, label, _ in METRICS:
        row = f"{label:30}" + "".join(f"{cols[k].get(key, 0):>10.1f}" for k in cols)
        print(row)
    out = os.path.join(root, "runs", datetime.datetime.now().strftime("%Y%m%dT%H%M%S") + "-compare-" + "-".join(versions) + ".json")
    json.dump(cols, open(out, "w"), indent=2)
    print(f"\nwrote {os.path.relpath(out)}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    if sys.argv[1] == "dir":
        print(json.dumps(score_dir(sys.argv[2]), indent=2))
    elif sys.argv[1] == "run":
        run(sys.argv[2])
    elif sys.argv[1] == "compare":
        compare(sys.argv[2:])
    else:
        sys.exit(__doc__)
