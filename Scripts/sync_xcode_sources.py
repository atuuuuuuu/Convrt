#!/usr/bin/env python3
"""Keep Convrt.xcodeproj in sync with the .swift files on disk (Xcode 15 has no folder sync).

Managed: Convrt target <- Convrt/Convrt/**/*.swift ; ConvrtTests target <- ConvrtTests/**/*.swift.
Every other .swift reference (except ConvrtUITests') is dropped, so stale duplicates disappear.
Usage: sync_xcode_sources.py [--check]   (--check exits 1 when the project is out of sync)
"""
import hashlib, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PBX = os.path.join(ROOT, "Convrt.xcodeproj", "project.pbxproj")

# (name, Sources phase id, group id, folder on disk relative to ROOT, group path on disk)
TARGETS = [
    ("Convrt",      "A6B7FA8D309875EC007D73CB", "A6B7FA93309875EC007D73CB", "Convrt"),
    ("ConvrtTests", "A6B7FA9E309875F6007D73CB", "A6B7FAA5309875F7007D73CB", "ConvrtTests"),
]
UITEST_PHASE = "A6B7FAA8309875F7007D73CB"


def gid(prefix, path):
    return prefix + hashlib.md5(path.encode()).hexdigest()[:22].upper()


def block(text, header_id):
    """Return (start, end) of the `{ ... };` object body that begins at `<id> /* .. */ = {`."""
    m = re.search(r"^\t\t%s /\*.*?\*/ = \{\n" % header_id, text, re.M)
    if not m:
        sys.exit("block not found: " + header_id)
    end = text.index("\n\t\t};\n", m.end()) + len("\n\t\t};\n")
    return m.start(), end


def list_ids(text, phase_id, key):
    s, e = block(text, phase_id)
    sub = text[s:e]
    m = re.search(r"\t\t\t%s = \(\n(.*?)\t\t\t\);" % key, sub, re.S)
    return re.findall(r"^\t+([0-9A-F]{24}) ", m.group(1), re.M)


def swift_files(folder):
    base = os.path.join(ROOT, folder)
    out = []
    for dp, dn, fn in os.walk(base):
        dn[:] = [d for d in dn if not d.endswith((".xcassets", ".xcodeproj")) and d != "Preview Content"]
        for f in fn:
            if f.endswith(".swift"):
                out.append(os.path.relpath(os.path.join(dp, f), base))
    return sorted(out)


def main():
    text = open(PBX, encoding="utf-8").read()
    original = text

    # build files -> file refs
    bf = dict(re.findall(r"^\t\t([0-9A-F]{24}) /\*.*?\*/ = \{isa = PBXBuildFile; fileRef = ([0-9A-F]{24})", text, re.M))
    keep_refs = {bf[b] for b in list_ids(text, UITEST_PHASE, "files") if b in bf}
    keep_bfs = {b for b, r in bf.items() if r in keep_refs}

    swift_refs = set(re.findall(r"^\t\t([0-9A-F]{24}) /\*.*?\*/ = \{isa = PBXFileReference;[^\n]*sourcecode\.swift", text, re.M))
    drop_refs = swift_refs - keep_refs
    drop_bfs = {b for b, r in bf.items() if r in drop_refs}
    drop = drop_refs | drop_bfs

    lines = text.split("\n")
    kept = []
    for ln in lines:
        m = re.match(r"^\t+([0-9A-F]{24}) /\*", ln)
        if m and m.group(1) in drop:
            continue
        kept.append(ln)
    text = "\n".join(kept)

    new_refs, new_bfs = [], []
    for name, phase, group, folder in TARGETS:
        files = swift_files(folder)
        refs, bfs = [], []
        for rel in files:
            ref, b = gid("C0", folder + "/" + rel), gid("C1", folder + "/" + rel)
            base = os.path.basename(rel)
            new_refs.append('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "%s"; sourceTree = "<group>"; };' % (ref, base, rel))
            new_bfs.append("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };" % (b, base, ref, base))
            refs.append("\t\t\t\t%s /* %s */," % (ref, base))
            bfs.append("\t\t\t\t%s /* %s in Sources */," % (b, base))
        # group children
        s, e = block(text, group)
        sub = text[s:e].replace("\t\t\tchildren = (\n", "\t\t\tchildren = (\n" + "\n".join(refs) + ("\n" if refs else ""), 1)
        text = text[:s] + sub + text[e:]
        # sources phase files (keep nothing old: rebuild list)
        s, e = block(text, phase)
        sub = text[s:e]
        sub = re.sub(r"(\t\t\tfiles = \(\n).*?(\t\t\t\);)", lambda m: m.group(1) + "\n".join(bfs) + ("\n" if bfs else "") + m.group(2), sub, count=1, flags=re.S)
        text = text[:s] + sub + text[e:]

    text = text.replace("/* End PBXBuildFile section */", "\n".join(new_bfs) + "\n/* End PBXBuildFile section */", 1)
    text = text.replace("/* End PBXFileReference section */", "\n".join(new_refs) + "\n/* End PBXFileReference section */", 1)
    text = re.sub(r"\n\n+(/\* End PBX)", r"\n\1", text)

    if "--check" in sys.argv:
        # idempotency check: running the transform again on its own output must not change it
        if text != original:
            print("project.pbxproj is out of sync; run Scripts/sync_xcode_sources.py")
            sys.exit(1)
        print("in sync")
        return
    if text != original:
        open(PBX, "w", encoding="utf-8").write(text)
        print("project.pbxproj updated")
    else:
        print("already in sync")


main()
