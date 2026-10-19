# shell-config

Source of truth for my zsh helpers (`zsh/`). `sync.sh` copies them into oh-my-zsh's
`custom/` directory, which oh-my-zsh loads at shell start. Sibling of
[agent-config](https://github.com/gokselkoksal/agent-config), and built the same way.

| Helper | Does | Configured by |
| --- | --- | --- |
| `goto <name>` | `cd` to a directory by name; completion shows the paths | `goto.conf` |
| `sshto <name>` | `ssh` to a host by name; completion shows the targets | `sshto.conf` |
| `xc …` | Xcode: `clean spm\|derived\|all`, `sim shake`, `open`, `version`; `xc sim …` passes through to `xcrun simctl` | nothing |
| `add-password`, `get-password`, `delete-password` | generic passwords in the macOS keychain, for `$USER` | nothing |
| `download-gif <url> [name]` | save a GIF to `$XDG_DOWNLOAD_DIR` or `~/Downloads` | nothing |

Run any of them without arguments for usage.

The helpers hold no paths or hosts. Those live in per-machine conf files that are never
committed and never written by sync, so the same files work on every machine.

## Install

Clone anywhere — the scripts work from wherever the repo lives. oh-my-zsh must be
installed (or see [Destinations](#destinations)).

```bash
git clone <this-repo-url>
cd shell-config
./bootstrap.sh
./sync.sh
```

Then create the conf files sync pointed at — it drops a `.example` beside each — and
open a new shell:

```bash
cd ~/.config/shell-config
cp goto.conf.example goto.conf
cp sshto.conf.example sshto.conf
```

Two steps because they answer different questions. `bootstrap.sh` prepares the
*checkout*: it checks that `git` and `zsh` are present (and names optional tools like
`jq` that a helper degrades without), says where sync will write, and installs the git
hooks. It copies nothing into your home directory — `sync.sh` does
that, and on a fresh clone you run it once by hand.

`bootstrap.sh` is idempotent: re-run it any time, and after pulling a change to
`git-hooks/`.

### Moving from hand-copied helpers

If `goto.zsh`, `sshto.zsh` or `xc.zsh` already sit in your `custom/` directory, the
first sync refuses with a name clash: those copies are not sync's to overwrite. Move
them away first, and move their hardcoded lists into the conf files:

```bash
mkdir -p ~/shell-config-old
mv ~/.oh-my-zsh/custom/{goto,sshto,xc}.zsh ~/shell-config-old/   # or delete them
```

Earlier versions of some helpers were oh-my-zsh plugins (`custom/plugins/goto/`,
`custom/plugins/password-management/`, `custom/plugins/utils/`), enabled through
`plugins=(…)` in `.zshrc`. Sync does not touch `plugins/`, so those keep loading — and
oh-my-zsh loads `custom/*.zsh` after plugins, so the synced copies win, with their own
listing format and the conf file instead of `GOTO_DIRS`. Remove the plugin folders and
their `plugins=(…)` entries once the synced ones work; `goto`'s `GOTO_DIRS` entries go
into `goto.conf`.

### Worktrees

**Run `./bootstrap.sh` in every new worktree.** `git worktree add` copies nothing and
runs nothing, so a fresh worktree is unprepared until you do. Hooks live in the shared
git dir, so a worktree usually finds them already installed and bootstrap says as much.

A worktree sitting on a feature branch never syncs on its own: both hooks check the
branch first, so committing, pushing, and pulling there leave `custom/` alone.

## Sync

What sync writes is a snapshot, so **re-run `./sync.sh` after every change here** —
editing a helper does nothing until you do, and then only in new shells.

That is for work you have not published yet. Once a change reaches the default branch
the hooks take over: pushing `main` syncs, and so does pulling onto it.

```bash
./sync.sh
```

| Source | Destination |
| --- | --- |
| `zsh/*.zsh` | `$ZSH_CUSTOM/` (default `~/.oh-my-zsh/custom/`), listed in a manifest there |
| `config/*.conf.example` | `~/.config/shell-config/`, next to the `.conf` files you write |

Sync writes only what it owns, so it never asks before writing, and hooks behave exactly
like a manual run.

### Destinations

Both are resolved the way the shell resolves them, so an override in your `.zshrc`
works for sync too as long as it is exported:

- **Custom dir:** `$ZSH_CUSTOM`, else `$ZSH/custom`, else `~/.oh-my-zsh/custom`. Sync
  creates it if missing, but only inside an oh-my-zsh that exists; without one it
  refuses. Without oh-my-zsh, set `ZSH_CUSTOM` to any directory and source its `*.zsh`
  files from your `.zshrc` yourself.
- **Conf dir:** `$SHELL_CONFIG_HOME`, else `${XDG_CONFIG_HOME:-~/.config}/shell-config`.
  The helpers read it at call time, so it must be set before you call them, not before
  they load.

### Helpers

Each `zsh/*.zsh` is copied as is. `$ZSH_CUSTOM/.gokselkoksal-shell-config.manifest`
lists the files sync put there, and those are the only ones it overwrites or removes: a
file deleted or renamed here is removed there. Anything not in the manifest — your own
`*.zsh`, oh-my-zsh's `plugins/` and `themes/` — is never modified or deleted.

`shell-config.zsh` is the shared part: it reads the conf files. The helpers call it when
they run, not when they load, so oh-my-zsh's alphabetical load order does not matter and
a conf edit takes effect on the next call without a new shell.

### Conf files

One `<helper>.conf` per helper, one entry per line: a name, whitespace, then the value to
the end of the line. Blank lines and `#` lines are skipped. In the value a leading `~`
and `$VARIABLES` are expanded — the file is trusted like `.zshrc`, so put nothing in it
you would not put there.

```
# goto.conf
docs   ~/Documents
repos  $HOME/Development/Repos
```

```
# sshto.conf — the value is what ssh gets: user@host, or a Host alias from ~/.ssh/config
studio  me@studio-mac-mini
```

Sync rewrites the `.example` files on every run and logs a hint for each `.conf` that is
missing. It never writes a `.conf`.

### When sync refuses

Everything is checked before anything is written. Any of these fails the run with the
full list, leaving every destination as it was:

- a repo file's name is already taken in `custom/` by something not in the manifest —
  the hand-copied version of the same helper, usually; move it away;
- a managed file has become a symlink or a directory;
- the custom dir does not exist and neither does its parent (no oh-my-zsh) — install it
  or set `ZSH_CUSTOM`;
- the custom dir, the conf dir, or a folder above either is a plain file or a symlink
  to nothing (a symlink to a directory is fine);
- a `.conf.example` in the conf dir is a symlink or not a regular file.

## Git hooks

`bootstrap.sh` installs `git-hooks/pre-push` and `git-hooks/post-merge` into
`.git/hooks`. Both fire only for the default branch:

| Hook | Fires when | Why |
| --- | --- | --- |
| `pre-push` | pushing the default branch | publishing on `main` is what makes a change real, so that is what installs it |
| `post-merge` | pulling onto the default branch | the same trigger seen from the receiving end, for changes published elsewhere |

Everything else — committing, pushing a feature branch, pulling in a worktree — changes
nothing outside the repo. Run `./sync.sh` when you want your helpers updated without
publishing.

`pre-push` runs *before* the push is accepted, since git has no post-push hook. A
rejected push therefore leaves the sync applied; the content was already committed on
your default branch, so this costs nothing. A failing sync never blocks the push — it
warns and lets it through.

Hooks run without a terminal, which changes nothing: sync never prompts. They remove
managed files that left the repo like a manual run does, since the manifest limits
deletion to what sync itself copied.

Sync reads the files of the checkout it runs in, so the hooks skip it, with a warning,
when those files are not what is being published: `pre-push` when the checkout is not at
the commit being pushed (pushing `main` from another branch's worktree), and either hook
when the checkout has uncommitted changes.

Both hooks run `sync.sh`, never `bootstrap.sh`: publishing should sync, not re-check
prerequisites. So a change to `git-hooks/` lands only when you run `./bootstrap.sh`
again — committing it is not enough.

A pre-existing hook that didn't come from this repo is left alone with a warning, and is
never removed.

## Adding a helper

1. Add `zsh/<name>.zsh`. Read any per-machine values through `_shell_config_lookup`,
   `_shell_config_names` and `_shell_config_list` from `shell-config.zsh`, at call time.
2. If it has values, add `config/<name>.conf.example` with placeholder entries — the
   repo is public.
3. Register completion only `if (( $+functions[compdef] ))`, so the file also loads,
   without an error status, where `compinit` has not run.
4. `./sync.sh`, open a new shell.
