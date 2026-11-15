# 28. A test that writes shell.json keeps it private

- Status: accepted
- Date: 2026-11-15
- Answers the maintainer review that blocked the marketplace update to `0.7.0`
  ([omacom/omarchy-plugin-marketplace#14197](https://github.com/omacom/omarchy-plugin-marketplace/issues/14197))
- Owns the file handling of `tests/full.py`; the CHANGELOG names this file

## Context

`tests/full.py` rewrites the operator's `shell.json` while it drives the bar,
and puts it back afterwards. The review found that it did both carelessly.
`write_config` wrote a fresh `.pocket-full` file with default permissions and
moved it over `shell.json`, so under umask `022` a `0600` config became `0644`,
readable by every local account that can reach the directory. `restore`
copied the contents back with `shutil.copyfile`, which keeps the permissions of
the file it writes into, so the widened mode outlived the run. The config on
the machine these tests run on is `0600`, so this was not hypothetical.

The host is not part of the problem. It saves `shell.json` through
`FileView { atomicWrites: true }` (`shell.qml`), and the file kept `0600`
through months of the host's own writes.

Reading the rest of the file handling for the same class of defect turned up
three more, none of them in the review:

- The snapshot was a `copyfile` into `$POCKET_SHOTS/shell.json.snapshot`, at
  `0644` under a fixed name. The default `mkdtemp` directory is `0700`, but an
  operator who points `POCKET_SHOTS` at a shared directory left a readable copy
  of the config there, and the snapshot was never deleted.
- `os.replace` onto a symlinked `shell.json` (a dotfiles checkout) replaced the
  link with a plain file, so the run quietly detached the config from its
  repository.
- The restore truncated and rewrote the file in place, so the shell could read
  it half written.

## Decision

**Every write of `shell.json` goes through `replace_config`.** It creates the
new file with `mkstemp` (private, exclusive, unguessable name) next to the file
the path resolves to, gives it the mode `snapshot()` recorded before writing a
byte, and moves it into place. `write_config` and `restore` both use it, so the
config is never wider than it was, not even for a moment, a symlink survives,
and the restore is atomic like every other write.

**The snapshot is a private `mkstemp` file in `$TMPDIR`**, not under
`$POCKET_SHOTS`, and it is deleted once the restore is confirmed. A failed
restore keeps it and prints where it is, as before.

`tests/live.sh` needed nothing: its backup comes from `mktemp` (`0600`), and
`cp` onto the existing `shell.json` keeps the config's own mode and follows a
symlink.

**Not done.** The run is not refused when `shell.json` belongs to another user
(a run under `sudo`). The documented path, `tests/live.sh --full`, runs as the
operator and checks that `/dev/uinput` is writable for them. Screenshots in a
`POCKET_SHOTS` the operator chose are written with the operator's umask, as any
tool writes to an output directory it was given.

## Consequences

`tests/config-mode-test.py` runs `snapshot()`, `write_config()` and `restore()`
on a `0600` config under umask `022`, as a plain file and as a symlink, and is
part of `tests/run.sh`. Each of its checks was watched failing against the old
file handling.

**The rule this file leaves behind.** A test that writes a file the user owns
writes it the way the user left it: same mode, same place behind a symlink, and
no copy lying around in a place the user did not pick.
