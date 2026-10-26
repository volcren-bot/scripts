#!/usr/bin/env python3
"""Keep docs/lib in sync with lib: stub missing docs/functions, flag orphaned docs."""
import argparse
import difflib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIB = ROOT / "lib"
DOCS = ROOT / "docs" / "lib"

FUNC_RE = re.compile(r"^function ([A-Za-z_]\w*)\.([A-Za-z_]\w*)(<[^>]*>)?\(", re.M)


def pascal(segment: str) -> str:
    return "".join(p[:1].upper() + p[1:] for p in segment.split("_"))


def title(rel: Path) -> str:
    return ".".join(pascal(p) for p in rel.with_suffix("").parts)


def parse_functions(src: str):
    """Yield (Mod.name, verbatim signature) for each column-0 public function."""
    for m in FUNC_RE.finditer(src):
        depth, i = 1, m.end()
        while i < len(src) and depth > 0:
            if src[i] == "(":
                depth += 1
            elif src[i] == ")":
                depth -= 1
            i += 1
        if depth:
            continue
        eol = src.find("\n", i)
        eol = len(src) if eol == -1 else eol
        rest = src[i:eol]
        end = eol if rest.lstrip().startswith(":") else i
        yield f"{m.group(1)}.{m.group(2)}", src[m.start():end].rstrip()


def git(*args: str) -> str:
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def doc_for(rel: Path) -> Path:
    return (DOCS / rel).with_suffix(".md")


SECTION_START = r"^(?:## |<!-- ## )"


def hide_section(text: str, name: str) -> str:
    """Wrap the `## name` section in an HTML comment, so the docs stop showing it."""
    head = re.search(rf"^## {re.escape(name)}[ \t]*$", text, re.M)
    if not head:
        return text
    nxt = re.search(SECTION_START, text[head.end():], re.M)
    end = head.end() + nxt.start() if nxt else len(text)
    body = text[head.start():end].rstrip("\n").replace("-->", "-- >")
    hidden = "<!-- " + body + "\n-->\n"
    return text[:head.start()] + hidden + ("\n" + text[end:] if nxt else "")


def unhide_section(text: str, name: str, sig: str) -> str:
    """Restore a section hidden by hide_section, updating its signature. No-op if absent."""
    m = re.search(rf"^<!-- (## {re.escape(name)}[ \t]*\n.*?)\n-->[ \t]*$", text, re.M | re.S)
    if not m:
        return text
    body = m.group(1).replace("-- >", "-->")
    body = re.sub(
        rf"(```luau\n)function {re.escape(name)}\b.*?(\n```)",
        lambda d: d.group(1) + sig + d.group(2),
        body,
        count=1,
        flags=re.S,
    )
    return text[:m.start()] + body + text[m.end():]


def pair_renames(old: dict, new: dict):
    """Pair removed functions with added ones: (old_name, new_name) by signature similarity."""
    removed = [n for n in old if n not in new]
    added = [n for n in new if n not in old]
    if len(removed) == 1 and len(added) == 1:
        return [(removed[0], added[0])]

    def body(name: str, sig: str) -> str:
        return sig.replace(name.split(".", 1)[1], "_", 1)

    scored = sorted(
        (
            (difflib.SequenceMatcher(None, body(r, old[r]), body(a, new[a])).ratio(), r, a)
            for r in removed
            for a in added
        ),
        reverse=True,
    )
    pairs, used_r, used_a = [], set(), set()
    for score, r, a in scored:
        if score >= 0.6 and r not in used_r and a not in used_a:
            pairs.append((r, a))
            used_r.add(r)
            used_a.add(a)
    return pairs


def rename_section(text: str, old: str, new: str, old_sig: str, new_sig: str) -> str:
    head = re.search(rf"^## {re.escape(old)}[ \t]*$", text, re.M)
    if not head or re.search(rf"^## {re.escape(new)}\s*$", text, re.M):
        return text
    nxt = re.search(SECTION_START, text[head.end():], re.M)
    end = head.end() + nxt.start() if nxt else len(text)
    section = text[head.start():end].replace(old_sig, new_sig)
    section = re.sub(rf"(?<![\w.]){re.escape(old)}\b", new, section)
    return text[:head.start()] + section + text[end:]


def apply_commit_renames(base: str, renamed_files: list, renamed_funcs: list, hidden_funcs: list):
    """Follow file and function renames between `base` and HEAD into docs."""
    out = git("diff", "--relative", "--name-status", "-M", base, "HEAD", "--", "lib")
    for line in out.splitlines():
        parts = line.split("\t")
        status = parts[0]
        if status[0] not in "MR":
            continue
        old_p, new_p = Path(parts[1]), Path(parts[-1])
        if old_p.suffix != ".luau" or new_p.suffix != ".luau":
            continue
        old_rel, new_rel = old_p.relative_to("lib"), new_p.relative_to("lib")
        old_doc, new_doc = doc_for(old_rel), doc_for(new_rel)
        if old_rel != new_rel and old_doc.exists() and not new_doc.exists():
            new_doc.parent.mkdir(parents=True, exist_ok=True)
            if subprocess.run(["git", "mv", str(old_doc), str(new_doc)], cwd=ROOT).returncode:
                old_doc.rename(new_doc)
            renamed_files.append((old_doc, new_doc))
        if not new_doc.exists():
            continue
        old_funcs = dict(parse_functions(git("show", f"{base}:{old_p}")))
        new_funcs = dict(parse_functions((ROOT / new_p).read_text()))
        text = original = new_doc.read_text()
        pairs = pair_renames(old_funcs, new_funcs)
        for o, n in pairs:
            text = rename_section(text, o, n, old_funcs[o], new_funcs[n])
            renamed_funcs.append((new_doc, o, n))
        paired = {o for o, _ in pairs}
        for o in old_funcs:
            if o not in new_funcs and o not in paired:
                hidden = hide_section(text, o)
                if hidden != text:
                    text = hidden
                    hidden_funcs.append((new_doc, o))
        if text != original:
            new_doc.write_text(text)


def stub(name: str, sig: str) -> str:
    return (
        f"## {name}\n\nDefinition:\n```luau\n{sig}\n```\nTODO...\n\n"
        f"Example:\n```luau\n\n```\n"
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", help="commit to diff against, to follow renames into docs")
    args = ap.parse_args()
    created, updated, renamed, unhidden = [], [], [], []
    moved_files, moved_funcs, hidden_funcs = [], [], []
    if args.base and not set(args.base) <= {"0"} and git("rev-parse", "--verify", args.base):
        apply_commit_renames(args.base, moved_files, moved_funcs, hidden_funcs)

    for path in sorted(LIB.rglob("*.luau")):
        rel = path.relative_to(LIB)
        if rel.parts[0] == "examples":
            continue
        doc = (DOCS / rel).with_suffix(".md")
        funcs = list(parse_functions(path.read_text()))

        if not doc.exists():
            doc.parent.mkdir(parents=True, exist_ok=True)
            text = f"# {title(rel)}\n\n" + "\n".join(stub(n, s) for n, s in funcs)
            doc.write_text(text.rstrip("\n") + "\n")
            created.append(doc)
            continue

        text = original = doc.read_text()
        first = next((l for l in text.splitlines() if l.strip()), "")
        if not first.startswith("# "):
            text = f"# {title(rel)}\n\n" + text.lstrip("\n")
        for name, sig in funcs:
            if not re.search(rf"^## {re.escape(name)}\s*$", text, re.M):
                restored = unhide_section(text, name, sig)
                if restored != text:
                    text = restored
                    unhidden.append((doc, name))
                else:
                    text = text.rstrip("\n") + "\n\n" + stub(name, sig)
        if text != original:
            doc.write_text(text)
            updated.append(doc)

    for doc in sorted(DOCS.rglob("*.md")):
        if doc.name.startswith("_"):
            continue
        if not (LIB / doc.relative_to(DOCS)).with_suffix(".luau").exists():
            new = doc.with_name("_" + doc.name)
            r = subprocess.run(["git", "mv", str(doc), str(new)], cwd=ROOT)
            if r.returncode:
                doc.rename(new)
            renamed.append((doc, new))

    rel = lambda p: p.relative_to(ROOT)
    for a, b in moved_files:
        print(f"moved {rel(a)} -> {rel(b)}")
    for d, o, n in moved_funcs:
        print(f"renamed {o} -> {n} in {rel(d)}")
    for d, n in unhidden:
        print(f"restored {n} in {rel(d)}")
    for d, n in hidden_funcs:
        print(f"hid {n} in {rel(d)}")
    for p in created:
        print(f"created {rel(p)}")
    for p in updated:
        print(f"updated {rel(p)}")
    for a, b in renamed:
        print(f"renamed {rel(a)} -> {rel(b)}")
    print(f"{len(created)} created, {len(updated)} updated, {len(renamed)} renamed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
