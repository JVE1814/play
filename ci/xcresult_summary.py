#!/usr/bin/env python3
"""Summarises an Xcode result bundle into plain-text files in ci-output/.

usage: xcresult_summary.py RESULT.xcresult OUT_DIR TEST_LOG
       xcresult_summary.py --rename-attachments EXPORT_DIR SCREENSHOT_DIR

Writes app-totals.txt (one line), test-results.txt (every test case) and appends failures to
failures.txt. Exits non-zero when any test failed or no tests ran.
"""
import json, os, re, shutil, subprocess, sys


def xcresulttool(*args):
    result = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", *args],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "xcresulttool failed")
    return json.loads(result.stdout)


def walk(nodes, path=()):
    for node in nodes or []:
        name = node.get("name", "?")
        if node.get("nodeType") == "Test Case":
            yield path, node
        yield from walk(node.get("children"), path + (name,))


def rename_attachments(export_dir, screenshot_dir):
    manifest_path = os.path.join(export_dir, "manifest.json")
    if not os.path.exists(manifest_path):
        print("no attachments manifest")
        return 0
    os.makedirs(screenshot_dir, exist_ok=True)
    with open(manifest_path) as f:
        manifest = json.load(f)
    count = 0
    for test in manifest:
        for attachment in test.get("attachments", []):
            name = attachment.get("suggestedHumanReadableName") or attachment["exportedFileName"]
            name = re.sub(r"_\d+_[0-9A-F-]{36}", "", name)
            if not name.endswith(".png"):
                name += ".png"
            shutil.copy(os.path.join(export_dir, attachment["exportedFileName"]), os.path.join(screenshot_dir, name))
            count += 1
    print(f"copied {count} attachments")
    return 0


def fallback_from_log(log_path):
    """Totals from xcodebuild output when the result bundle cannot be read."""
    total = failed = 0
    with open(log_path, errors="replace") as f:
        text = f.read()
    for match in re.finditer(r"Test Suite '(?:All tests|[^']+\.xctest)' (?:passed|failed).*?\n\s*Executed (\d+) tests?, with (\d+) failures?", text):
        total += int(match.group(1))
        failed += int(match.group(2))
    failures = sorted(set(re.findall(r"^.*error: -\[.*$|^.*\.swift:\d+: error: .*$", text, re.M)))
    return total, failed, failures


def main():
    if sys.argv[1] == "--rename-attachments":
        return rename_attachments(sys.argv[2], sys.argv[3])
    bundle, out, log = sys.argv[1], sys.argv[2], sys.argv[3]
    lines, failures = [], []
    try:
        summary = xcresulttool("summary", "--path", bundle)
        tests = xcresulttool("tests", "--path", bundle)
        with open(os.path.join(out, "xcresult-summary.json"), "w") as f:
            json.dump(summary, f, indent=2)
        total = summary.get("totalTestCount", 0)
        passed = summary.get("passedTests", 0)
        failed = summary.get("failedTests", 0)
        skipped = summary.get("skippedTests", 0)
        expected = summary.get("expectedFailures", 0)
        for failure in summary.get("testFailures", []):
            failures.append(f"{failure.get('targetName', '?')} {failure.get('testName', '?')}: {failure.get('failureText', '')}")
        for path, node in walk(tests.get("testNodes")):
            suite = "/".join(p for p in path[1:])
            lines.append(f"{node.get('result', '?'):8} {suite}/{node.get('name')} ({node.get('duration', '?')})")
            if node.get("result") == "Failed":
                for child in node.get("children") or []:
                    if child.get("nodeType") == "Failure Message":
                        failures.append(f"{suite}/{node.get('name')}: {child.get('name')}")
        totals = (f"app unit + UI (xcodebuild): {total} tests, {passed} passed, {failed} failed, "
                  f"{skipped} skipped, {expected} expected failures")
    except Exception as error:  # fall back to the log
        print(f"result bundle unreadable ({error}); using the xcodebuild log")
        total, failed, failures = fallback_from_log(log)
        passed, skipped = total - failed, 0
        totals = f"app unit + UI (xcodebuild log): {total} tests, {passed} passed, {failed} failed, 0 skipped"
    with open(os.path.join(out, "app-totals.txt"), "w") as f:
        f.write(totals + "\n")
    with open(os.path.join(out, "test-results.txt"), "w") as f:
        f.write("\n".join(lines) + ("\n" if lines else ""))
    if failures:
        with open(os.path.join(out, "failures.txt"), "a") as f:
            f.write("\n".join(sorted(set(failures))) + "\n")
    print(totals)
    for line in failures:
        print("  " + line)
    return 0 if (total > 0 and failed == 0) else 1


if __name__ == "__main__":
    sys.exit(main())
