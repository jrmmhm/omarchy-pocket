#!/usr/bin/env python3
"""tests/full.py writes the operator's shell.json; it must not widen who can read it.

Drives the three writers full.py uses -- snapshot(), write_config() through
set_entry(), restore() -- on a private (0600) shell.json under umask 022, once
as a plain file and once as a symlink into a dotfiles directory. No shell, no
pointer: only the file handling runs.
"""

import json
import os
import shutil
import stat
import sys
import tempfile

WORK = tempfile.mkdtemp(prefix="pocket-mode-test-")
tempfile.tempdir = WORK  # snapshot()'s mkstemp lands here, removed with the rest
os.environ["XDG_CONFIG_HOME"] = os.path.join(WORK, "config")
os.environ["POCKET_SHOTS"] = os.path.join(WORK, "shots")
os.makedirs(os.environ["POCKET_SHOTS"])
os.umask(0o022)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import full  # noqa: E402

full.time.sleep = lambda _seconds: None

ORIGINAL = {"version": 1, "bar": {"layout": {"right": [{"id": full.P.SELF, "members": "a"}]}}}
FAILED = []


def check(name, ok, detail=""):
    print("%s %s%s" % ("PASS" if ok else "FAIL", name, " (%s)" % detail if detail else ""))
    if not ok:
        FAILED.append(name)


def mode(path):
    return "%o" % stat.S_IMODE(os.stat(path).st_mode)


def run(case, linked):
    base = os.path.join(WORK, case)
    config = os.path.join(base, "omarchy", "shell.json")
    real = os.path.join(base, "dotfiles", "shell.json") if linked else config
    os.makedirs(os.path.dirname(config))
    os.makedirs(os.path.dirname(real), exist_ok=True)
    fd = os.open(real, os.O_WRONLY | os.O_CREAT, 0o600)
    with os.fdopen(fd, "w") as handle:
        json.dump(ORIGINAL, handle)
    if linked:
        os.symlink(real, config)
    full.CONFIG = config

    master = full.snapshot()
    check("%s: the snapshot is as private as shell.json" % case, mode(master) == "600",
          "mode %s" % mode(master))

    full.set_entry(pinned="eDP-1")
    entry = json.load(open(config))["bar"]["layout"]["right"][0]
    check("%s: a written shell.json carries the write" % case, entry.get("pinned") == "eDP-1",
          "entry %s" % entry)
    check("%s: a written shell.json stays private" % case, mode(config) == "600",
          "mode %s" % mode(config))
    if linked:
        check("%s: a written shell.json is still the symlink" % case, os.path.islink(config))

    # Widened behind the test's back, as a run before this fix left it.
    os.chmod(real, 0o644)
    ok = full.restore(master)
    check("%s: restore reports the contents back" % case, ok)
    check("%s: restore puts the contents back" % case, json.load(open(config)) == ORIGINAL)
    check("%s: restore puts the permissions back" % case, mode(config) == "600",
          "mode %s" % mode(config))
    if linked:
        check("%s: restore leaves the symlink in place" % case, os.path.islink(config))


run("plain", linked=False)
run("symlink", linked=True)
shutil.rmtree(WORK)
print("CONFIG MODE %s (%d failed)" % ("PASSED" if not FAILED else "FAILED", len(FAILED)))
sys.exit(1 if FAILED else 0)
