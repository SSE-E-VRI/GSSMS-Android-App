"""
run_all.py
Executes the full report parity pipeline:
0. npx vite build (tool/report_parity/web) -- vite preview serves dist/, so rebuild it
1. node tool/report_parity/web/render_web.mjs
2. flutter test test/report_parity/render_android_test.dart with REPORT_PARITY_OUT
3. py tool/report_parity/compare.py   (exit 1 on any threshold failure)
"""
import os
import sys
import subprocess

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
WEB_DIR = os.path.join(ROOT_DIR, 'tool', 'report_parity', 'web')


def run_cmd(cmd, env=None, cwd=ROOT_DIR):
    print(f"\n>>> Running: {cmd}")
    res = subprocess.run(cmd, shell=True, cwd=cwd, env=env)
    if res.returncode != 0:
        print(f"Command failed with exit code {res.returncode}: {cmd}")
        return False
    return True


def main():
    # 0. Rebuild the web bundle so fixture/source edits are never rendered stale
    if not run_cmd("npx vite build", cwd=WEB_DIR):
        sys.exit(1)

    # 1. Render web
    if not run_cmd("node tool/report_parity/web/render_web.mjs"):
        sys.exit(1)

    # 2. Render android
    env = os.environ.copy()
    env["REPORT_PARITY_OUT"] = os.path.join("build", "report_parity", "android")
    if not run_cmd("flutter test test/report_parity/render_android_test.dart", env=env):
        sys.exit(1)

    # 3. Compare (non-zero exit when any fixture fails a threshold)
    ok = run_cmd("py tool/report_parity/compare.py")
    print("\nAll pipeline stages completed." if ok else "\nPipeline finished with threshold failures.")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
