"""Check locked hosted Dart packages against OSV (Python standard library only)."""
import datetime
import json
from pathlib import Path
import re
import sys
import urllib.request


def check(lockfile):
    text = Path(lockfile).read_text(encoding="utf-8")
    packages = []
    for name, block in re.findall(r"^  ([a-zA-Z0-9_]+):\n(.*?)(?=^  [a-zA-Z0-9_]+:|^sdks:|\Z)", text, re.M | re.S):
        version = re.search(r'^    version: "([^\"]+)"', block, re.M)
        if "    source: hosted" in block and version:
            packages.append({"package": {"name": name, "ecosystem": "Pub"}, "version": version.group(1)})
    if not packages:
        raise RuntimeError("No hosted packages found; refusing an empty scan")
    return query_packages(packages, "Pub")


def query_packages(packages, ecosystem):
    pending = [(i, query) for i, query in enumerate(packages)]
    findings = {}
    while pending:
        body = json.dumps({"queries": [query for _, query in pending]}).encode()
        request = urllib.request.Request("https://api.osv.dev/v1/querybatch", data=body, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=45) as response:
            results = json.load(response)["results"]
        if len(results) != len(pending):
            raise RuntimeError("Incomplete OSV response")
        more = []
        for (index, query), result in zip(pending, results):
            for vuln in result.get("vulns", []):
                findings.setdefault(index, set()).add(vuln["id"])
            if result.get("next_page_token"):
                more.append((index, {**query, "page_token": result["next_page_token"]}))
        pending = more
    return {"checked_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "source": "https://api.osv.dev/v1/querybatch", "ecosystem": ecosystem,
            "packages_checked": len(packages), "limitations": "Known OSV advisories for the specified resolved package ecosystem only; excludes bundled SDK binaries and unpublished vulnerabilities.",
            "findings": [{**packages[i], "advisories": sorted(ids)} for i, ids in sorted(findings.items())]}


if __name__ == "__main__":
    report = check(sys.argv[1] if len(sys.argv) > 1 else "pubspec.lock")
    output = Path("build/production-pub-advisories.json")
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Checked {report['packages_checked']} hosted packages; {len(report['findings'])} packages have advisories. Report: {output}")
    sys.exit(1 if report["findings"] else 0)
