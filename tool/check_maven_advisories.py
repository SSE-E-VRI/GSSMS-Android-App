"""Query OSV using an exported Gradle prodReleaseRuntimeClasspath graph."""
import json
from pathlib import Path
import re
import sys
from check_pub_advisories import query_packages

text = Path("build/production-maven-dependencies.txt").read_text(encoding="utf-8-sig")
if "BUILD SUCCESSFUL" not in text or "prodReleaseRuntimeClasspath" not in text:
    raise RuntimeError("A complete successful production dependency export is required")
resolved = set()
for line in text.splitlines():
    match = re.search(r"([A-Za-z0-9_.-]+):([A-Za-z0-9_.-]+):([^ ()]+)", line)
    if not match:
        continue
    group, name, version = match.groups()
    if " -> " in line:
        selected = line.split(" -> ", 1)[1].split()[0]
        parts = selected.split(":")
        if len(parts) == 3:
            group, name, version = parts
        else:
            version = selected
    if version.startswith("{"):
        continue
    resolved.add((group + ":" + name, version))
if not resolved:
    raise RuntimeError("No resolved Maven packages found")
queries = [{"package": {"name": name, "ecosystem": "Maven"}, "version": version} for name, version in sorted(resolved)]
report = query_packages(queries, "Maven")
output = Path("build/production-maven-advisories.json")
output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(f"Checked {report['packages_checked']} resolved Maven coordinates; {len(report['findings'])} packages have advisories. Report: {output}")
sys.exit(1 if report["findings"] else 0)
