"""
run_all.py
Executes the full report parity pipeline:
1. node tool/report_parity/web/render_web.mjs
2. flutter test test/report_parity/render_android_test.dart with REPORT_PARITY_OUT
3. py tool/report_parity/compare.py
"""
import os
import sys
import subprocess

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

def run_cmd(cmd, env=None, cwd=ROOT_DIR):
    print(f"\n>>> Running: {cmd}")
    res = subprocess.run(cmd, shell=True, cwd=cwd, env=env)
    if res.returncode != 0:
        print(f"Command failed with exit code {res.returncode}: {cmd}")
        return False
    return True

def main():
    # 1. Render web
    if not run_cmd("node tool/report_parity/web/render_web.mjs"):
        sys.exit(1)

    # 2. Render android
    env = os.environ.copy()
    env["REPORT_PARITY_OUT"] = os.path.join("build", "report_parity", "android")
    if not run_cmd("flutter test test/report_parity/render_android_test.dart", env=env):
        sys.exit(1)

    # 3. Compare
    if not run_cmd("py tool/report_parity/compare.py"):
        sys.exit(1)

    print("\nAll pipeline stages completed.")

if __name__ == "__main__":
    main()
