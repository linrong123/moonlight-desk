#!/usr/bin/env python3
"""Check shipped Mach-O dependencies, without relying on a local Qt install."""
import pathlib
import subprocess
import sys

bundle = pathlib.Path(sys.argv[1]).resolve()
if len(sys.argv) > 2:
    unexpected = [line for line in pathlib.Path(sys.argv[2]).read_text().splitlines()
                  if line.startswith("ERROR:") and "libmimerapi.dylib" not in line]
    if unexpected:
        raise SystemExit("macdeployqt failed:\n" + "\n".join(unexpected))
contents = bundle / "Contents"
frameworks = contents / "Frameworks"
executable_dir = contents / "MacOS"
# macdeployqt includes all SQL drivers via Qt's QML dependency closure. Mimer
# requires a separately installed commercial client and is not used by Office.
unused = contents / "PlugIns/sqldrivers/libqsqlmimer.dylib"
unused.unlink(missing_ok=True)

magic = {b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf",
         b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
         b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}
seen = set()
errors = []
checked = 0
for path in contents.rglob("*"):
    if not path.is_file() or path.resolve() in seen:
        continue
    seen.add(path.resolve())
    with path.open("rb") as stream:
        if stream.read(4) not in magic:
            continue
    checked += 1
    result = subprocess.check_output(["otool", "-L", str(path)], text=True)
    for line in result.splitlines():
        if not line.startswith("\t"):
            continue
        dep = line.strip().split(" (compatibility", 1)[0]
        if dep.startswith(("/System/Library/", "/usr/lib/")):
            continue
        candidates = []
        if dep.startswith("@loader_path/"):
            candidates = [path.parent / dep[len("@loader_path/"):]]
        elif dep.startswith("@executable_path/"):
            candidates = [executable_dir / dep[len("@executable_path/"):]]
        elif dep.startswith("@rpath/"):
            candidates = [frameworks / dep[len("@rpath/"):], path.parent / dep[len("@rpath/"):]]
        if not any(p.is_file() and p.resolve().is_relative_to(bundle) for p in candidates):
            errors.append(f"{path.relative_to(bundle)} -> {dep}")
if errors:
    raise SystemExit("Unbundled dependencies:\n" + "\n".join(sorted(set(errors))))
print(f"PASS: {checked} Mach-O files have self-contained non-system dependencies")
