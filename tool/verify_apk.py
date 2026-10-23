"""Inspect APK ZIP integrity, case collisions and native ELF page alignment."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import zipfile


def verify(path):
    path = Path(path)
    problems = []
    libraries = []
    with zipfile.ZipFile(path) as archive:
        bad = archive.testzip()
        if bad:
            problems.append(f"Corrupt ZIP entry: {bad}")
        names = {}
        for item in archive.infolist():
            key = item.filename.casefold()
            if key in names:
                problems.append(f"Case-insensitive collision: {names[key]} / {item.filename}")
            names[key] = item.filename
            if not item.filename.startswith("lib/") or not item.filename.endswith(".so"):
                continue
            data = archive.read(item)
            if data[:4] != b"\x7fELF":
                problems.append(f"Invalid native library: {item.filename}")
                continue
            endian = "<" if data[5] == 1 else ">"
            is64 = data[4] == 2
            phoff = struct.unpack_from(endian + ("Q" if is64 else "I"), data, 32 if is64 else 28)[0]
            entsize, count = struct.unpack_from(endian + "HH", data, 54 if is64 else 42)
            alignments = []
            for index in range(count):
                offset = phoff + index * entsize
                kind = struct.unpack_from(endian + "I", data, offset)[0]
                if kind == 1:
                    alignments.append(struct.unpack_from(endian + ("Q" if is64 else "I"), data, offset + (48 if is64 else 28))[0])
            # Android's 16 KB requirement applies to the 64-bit ABIs;
            # 32-bit Android remains on 4 KB pages (NDK maintainer guide).
            required_alignment = 16384 if is64 else 4096
            if not alignments or min(alignments) < required_alignment:
                problems.append(f"Insufficient native LOAD alignment: {item.filename}")
            libraries.append({"path": item.filename, "load_alignments": alignments, "required_alignment": required_alignment})
    if not libraries:
        problems.append("APK has no native libraries")
    return {"apk": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "bytes": path.stat().st_size, "native_libraries": libraries, "problems": problems,
            "limitations": "Signature, manifest policy, runtime behavior and backend compatibility require separate checks."}


if __name__ == "__main__":
    report = verify(sys.argv[1])
    output = Path("build/production-apk-inspection.json")
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Inspected {len(report['native_libraries'])} native libraries; {len(report['problems'])} problems. SHA256 {report['sha256']}")
    for problem in report["problems"]:
        print(problem)
    sys.exit(1 if report["problems"] else 0)
