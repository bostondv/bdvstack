#!/usr/bin/env python3
"""Generate report.html from the fixtures and every arm in rewrites/.

Usage: python3 report.py [--publish]
Arms are discovered, so adding rewrites/v4 makes it appear on the next run.
"""
import os, re, sys, json, html, glob, datetime
import score

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "report.html")

METRICS = [
    ("words", "Words", "lower"),
    ("longest_sentence", "Longest sentence", "lower"),
    ("max_sentences_per_paragraph", "Max sentences / paragraph", "lower"),
    ("first_actionable_word", "First actionable word", "lower"),
    ("tables", "Tables", "higher"),
    ("figures", "Figures", "higher"),
    ("em_dashes", "Em dashes", "lower"),
    ("unlinked_refs", "Unlinked ticket/PR refs", "lower"),
    ("pr_template_pct", "PR template headings %", "higher"),
    ("flesch", "Flesch reading ease", "higher"),
    ("fk_grade", "Flesch-Kincaid grade", "lower"),
    ("fog", "Gunning Fog", "lower"),
    ("smog", "SMOG", "lower"),
    ("ari", "ARI", "lower"),
    ("coleman_liau", "Coleman-Liau", "lower"),
    ("polysyllable_pct", "% words 3+ syllables", "lower"),
]

def arms():
    found = sorted(os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(ROOT, "rewrites", "*", "")) if os.path.isdir(p))
    return found or [d.split("/")[-1] for d in glob.glob(os.path.join(ROOT, "rewrites", "*"))]

def inline(s):
    codes = []
    def stash(m):
        codes.append(m.group(1)); return f"\x00{len(codes)-1}\x00"
    s = re.sub(r"`([^`]+)`", stash, s)
    s = html.escape(s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"\*([^*]+)\*", r"<em>\1</em>", s)
    s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', s)
    return re.sub(r"\x00(\d+)\x00", lambda m: "<code>" + html.escape(codes[int(m.group(1))]) + "</code>", s)

def md(text):
    lines, out, buf, i = text.split("\n"), [], [], 0
    def flush():
        if buf: out.append("<p>" + inline(" ".join(buf)) + "</p>"); buf.clear()
    while i < len(lines):
        s = lines[i].strip()
        if not s:
            flush(); i += 1; continue
        if s.startswith("```"):
            flush(); i += 1; blk = []
            while i < len(lines) and not lines[i].strip().startswith("```"):
                blk.append(lines[i]); i += 1
            i += 1
            out.append("<pre><code>" + html.escape("\n".join(blk)) + "</code></pre>"); continue
        if s.startswith("#"):
            flush(); lv = len(s) - len(s.lstrip("#"))
            out.append(f"<h{lv+2}>" + inline(s[lv:].strip()) + f"</h{lv+2}>"); i += 1; continue
        if s.startswith("|"):
            flush(); rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(lines[i].strip()); i += 1
            cells = [[c.strip() for c in r.strip("|").split("|")] for r in rows if not re.match(r"^\|[\s:|-]+\|?$", r)]
            if not cells: continue
            t = "<table><thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in cells[0]) + "</tr></thead><tbody>"
            for r in cells[1:]:
                t += "<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>"
            out.append(t + "</tbody></table>"); continue
        if re.match(r"^[-*]\s", s):
            flush(); items = []
            while i < len(lines) and re.match(r"^[-*]\s", lines[i].strip()):
                items.append("<li>" + inline(lines[i].strip()[2:]) + "</li>"); i += 1
            out.append("<ul>" + "".join(items) + "</ul>"); continue
        if re.match(r"^\d+\.\s", s):
            flush(); items = []
            while i < len(lines) and re.match(r"^\d+\.\s", lines[i].strip()):
                items.append("<li>" + inline(re.sub(r"^\d+\.\s", "", lines[i].strip())) + "</li>"); i += 1
            out.append("<ol>" + "".join(items) + "</ol>"); continue
        buf.append(s); i += 1
    flush()
    return "\n".join(out)

def build():
    versions = arms()
    fixtures = sorted(os.path.basename(p) for p in glob.glob(os.path.join(ROOT, "fixtures", "*.md")))
    base = score.agg(score.score_dir(os.path.join(ROOT, "fixtures")))
    cols = {"baseline": base}
    for v in versions:
        d = os.path.join(ROOT, "rewrites", v)
        if os.path.isdir(d): cols[v] = score.agg(score.score_dir(d))
    latest = versions[-1] if versions else None
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")

    def row(key):
        vals = [cols[k].get(key, 0) for k in cols]
        best = max(vals) if dict((m, d) for m, _, d in METRICS)[key] == "higher" else min(vals)
        cells = "".join(f'<td class="{"win" if abs(v-best)<1e-9 and k!=list(cols)[0] else ""}">{v:g}</td>' for k, v in zip(cols, vals))
        return f"<tr><td>{dict((m, l) for m, l, _ in METRICS)[key]}</td>{cells}</tr>"

    heads = "".join(f"<th>{k}</th>" for k in cols)
    metric_rows = "".join(row(m) for m, _, _ in METRICS[:8])
    read_rows = "".join(row(m) for m, _, _ in METRICS[7:])

    verdict = ""
    if latest:
        f0, f1 = base.get("flesch", 0), cols[latest].get("flesch", 0)
        verdict = (f"{latest} reads easiest: Flesch {f1:g}, up {f1-f0:.1f} from baseline. "
                   f"{cols[latest]['words']:g} words against {base['words']:g}, and the ask lands at word "
                   f"{cols[latest]['first_actionable_word']:g} against {base['first_actionable_word']:g}.")

    doc_sections = []
    for f in fixtures:
        base_md = open(os.path.join(ROOT, "fixtures", f)).read()
        panes = ['<div class="pane"><div class="pane-h">Baseline</div><div class="doc">' + md(base_md) + "</div></div>"]
        for v in versions:
            p = os.path.join(ROOT, "rewrites", v, f)
            if os.path.exists(p):
                panes.append(f'<div class="pane"><div class="pane-h">{v}</div><div class="doc">' + md(open(p).read()) + "</div></div>")
        inner = "".join(panes)
        doc_sections.append(f'<section class="example"><h2>{f}</h2><div class="panes">{inner}</div></section>')

    body = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Writing eval — {ts}</title>
<style>
:root{{--ink:#15181d;--muted:#6b7280;--line:#e4e6eb;--bg:#fdfdfc;--accent:#2f5bea;--good:#0f7b52}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--ink);font:16px/1.6 ui-sans-serif,-apple-system,"Segoe UI",sans-serif}}
.wrap{{max-width:1180px;margin:0 auto;padding:0 26px}}
h1{{font-size:34px;letter-spacing:-.02em;margin:44px 0 10px;font-weight:650}}
h2{{font-size:13px;text-transform:uppercase;letter-spacing:.09em;color:var(--muted);margin:52px 0 8px;font-weight:600}}
h3,h4,h5{{margin:18px 0 6px}}
p.lead{{font-size:17px;color:#33383f;max-width:70ch;margin:0 0 22px}}
table{{width:100%;border-collapse:collapse;font-size:14px;background:#fff}}
th{{text-align:left;font-size:11.5px;text-transform:uppercase;letter-spacing:.07em;color:var(--muted);padding:8px 10px;border-bottom:1px solid var(--line)}}
td{{padding:8px 10px;border-bottom:1px solid var(--line);font-variant-numeric:tabular-nums}}
td.win{{color:var(--good);font-weight:640}}
th.cur{{color:var(--ink);background:#eef2ff;border-radius:6px 6px 0 0}}
.panes{{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:16px;align-items:start}}
.doc{{border:1px solid var(--line);border-radius:10px;padding:14px 16px;background:#fff;font-size:13.5px;line-height:1.55;max-height:520px;overflow:auto}}
.doc p{{margin:0 0 10px}}.doc table{{font-size:12.5px;margin:6px 0 10px}}.doc th{{background:#f6f6f5;text-transform:none;letter-spacing:0}}
.doc code{{background:#eef0f3;padding:1px 4px;border-radius:4px;font-size:12px}}
.doc pre{{background:#f4f5f7;border-radius:8px;padding:10px;overflow:auto;font-size:11.5px}}
.pane-h{{font-size:11.5px;text-transform:uppercase;letter-spacing:.07em;color:var(--muted);margin-bottom:6px}}
.example{{margin-bottom:34px}}footer{{margin:60px 0;padding-top:20px;border-top:1px solid var(--line);font-size:13px;color:var(--muted)}}
</style></head><body><main class="wrap">
<h1>Writing eval</h1>
<p class="lead">{verdict}</p>
<table><thead><tr><th>Metric</th>{heads}</tr></thead><tbody>{metric_rows}</tbody></table>
<h2>Readability</h2>
<table><thead><tr><th>Metric</th>{heads}</tr></thead><tbody>{read_rows}</tbody></table>
<h2>Examples</h2>
{chr(10).join(doc_sections)}
<footer>Generated by <code>eval/report.py</code> at {ts}. Baseline is the document as it stands; current is the rules in force. Re-run <code>./run.sh current</code> to regenerate.</footer>
</main></body></html>"""
    open(OUT, "w").write(body)
    print(f"wrote {os.path.relpath(OUT)} ({len(body)//1024} KB), arms: {', '.join(versions)}")
    return OUT

if __name__ == "__main__":
    path = build()
    if "--publish" in sys.argv:
        print("publish with: pastry update <slug> --no-add -f", path)
