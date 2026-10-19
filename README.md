# shell-config

Source of truth for my zsh helpers (`zsh/`). `sync.sh` copies them into oh-my-zsh's
`custom/` directory, which oh-my-zsh loads at shell start. Sibling of
[agent-config](https://github.com/gokselkoksal/agent-config), and built the same way.

| Helper | Does | Configured by |
| --- | --- | --- |
| `goto [<name>]` | `cd` to a directory by name, and `~name` for every entry | `goto.conf` |
| `secret set\|get\|copy\|rm <service>`, `secret list` | secrets in the macOS keychain | nothing |
| `xc clean\|sim\|open\|version …` | Xcode: caches, simulators, workspaces, the active Xcode | nothing |
| `download <url> [name]` | save a URL to `$XDG_DOWNLOAD_DIR` or `~/Downloads` | nothing |

Run any of them without arguments, or with `-h`, for usage. The helpers hold no paths or
hosts: those live in per-machine conf files that are never committed and never written
by sync, so the same files work on every machine.

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
```

Two steps because they answer different questions. `bootstrap.sh` prepares the
*checkout*: it checks that `git` and `zsh` are present (and names optional tools like
`jq` that a helper degrades without), says where sync will write, and installs the git
hooks. It copies nothing into your home directory — `sync.sh` does that, and on a fresh
clone you run it once by hand.

`bootstrap.sh` is idempotent: re-run it any time, and after pulling a change to
`git-hooks/`.

### Moving from hand-copied helpers

If `goto.zsh`, `sshto.zsh` or `xc.zsh` already sit in your `custom/` directory, the
first sync refuses with a name clash: those copies are not sync's to overwrite. Move
them away first:

```bash
mkdir -p ~/shell-config-old
mv ~/.oh-my-zsh/custom/{goto,sshto,xc}.zsh ~/shell-config-old/   # or delete them
```

Then move what they hardcoded:

- `goto`'s list, or the `GOTO_DIRS` of the plugin version, goes into `goto.conf`.
- `sshto`'s hosts go into `~/.ssh/config`, which `ssh`, `scp`, `rsync` and zsh
  completion all read, and which has room for the per-host options `sshto` never had:

  ```
  Host mirana
      HostName miranas-mac-mini
      User mirana
  ```

  There is no `sshto` here: `ssh mirana` is the whole feature.
- `add-password`, `get-password` and `delete-password` are `secret set|get|rm`. Items
  stored by the old functions have no tag, so `secret list` does not show them and
  `secret rm` will not remove them; `secret set` the same service once to adopt one.
- `download-gif` is `download`; pass a name when the URL has no extension.

Earlier versions of some helpers were oh-my-zsh plugins (`custom/plugins/goto/`,
`custom/plugins/password-management/`, `custom/plugins/utils/`), enabled through
`plugins=(…)` in `.zshrc`. Sync does not touch `plugins/`, and oh-my-zsh loads
`custom/*.zsh` after plugins, so a synced `goto` wins over the plugin one while both are
installed. Remove the plugin folders and their `plugins=(…)` entries once the synced
helpers work.

### Worktrees

**Run `./bootstrap.sh` in every new worktree.** `git worktree add` copies nothing and
runs nothing, so a fresh worktree is unprepared until you do. Hooks live in the shared
git dir, so a worktree usually finds them already installed and bootstrap says as much.

A worktree sitting on a feature branch never syncs on its own: both hooks check the
branch first, so committing, pushing, and pulling there leave `custom/` alone.

## Helpers

### Conventions

Every helper has the same shape, so the same things work everywhere:

- bare, `-h` or `--help` prints usage on stdout and exits 0;
- a command it does not have, or an argument it needs and did not get, prints one
  `helper: …` line and the usage on stderr and exits 2;
- a failure at runtime prints one `helper: …` line on stderr and exits 1;
- success is silent, unless the output is the result (`secret get`, `download` prints
  the saved path) or something was deleted (`xc clean`).

Subcommands are `helper <noun> <verb>`, never `verb-noun` functions in the global
namespace: `secret set`, not `add-password`.

### goto

```
goto            list name -> directory
goto <name>     cd there
```

Every entry whose name is a valid identifier is also a zsh named directory, so
`~repos/koin` works in any command, with zsh's own completion. Those are set when the
helper loads and refreshed on each `goto` call, so a conf edit reaches them without a
new shell.

### secret

```
secret set <service>     add or update; security itself asks for the value
secret get <service>     print it
secret copy <service>    clipboard, never printed
secret rm <service>
secret list
```

Each one is a generic password in the login keychain for the current account, tagged
with a fixed comment. `list` and `rm` act only on items with that tag, so nothing else in
the keychain can be listed or removed through them. `set` passes no value on the command
line: `security` prompts for it with echo off, so it never reaches history or `ps`.

### xc

```
xc clean spm | derived [project] | all
xc sim shake [all | <udid>]        pick from the booted simulators (needs jq), all, or one
xc sim <args…>                     xcrun simctl
xc open [<query> | --list]         the workspace here, or the one below here whose name matches
xc version [path | use <version|app> | reset]
```

`xc open` offers to close other workspaces Xcode has open from the same directory
first. `xc version use 16.2` switches to `/Applications/Xcode-16.2.app`, `xc version use
Xcode-beta` to `/Applications/Xcode-beta.app`; `use` and `reset` run `xcode-select`
under `sudo`.

### download

```
download <url> [name]
```

Saves to `$XDG_DOWNLOAD_DIR`, else `~/Downloads`, named after the URL's last path
segment unless a name is given, and prints the path. Fails on an HTTP error instead of
saving the error page.

### Adding a helper

1. Add `zsh/<name>.zsh`. For subcommands, declare one table and dispatch from it:

   ```zsh
   typeset -ga _name_commands=(
       'start <thing>'   'Start a thing'
       'stop [--all]'    'Stop one, or all'
   )
   name() { _shell_config_dispatch name "$@" }
   _name_start() { … }
   _name_stop()  { … }
   _name_complete() { _shell_config_complete name }
   if (( $+functions[compdef] )); then compdef _name_complete name; fi
   ```

   `name start x` runs `_name_start x`: the leading words of each key, up to the first
   `<arg>`, `[opt]` or `-flag`, name the function. Usage and completion come from the
   same table. Arguments past the command words complete through
   `_name_complete_args`, if defined; arguments the table does not cover dispatch to
   `_name_fallback`, if defined. Report problems with `_shell_config_usage_error` (exit
   2) and `_shell_config_error` (exit 1).
2. Per-machine values are read through `_shell_config_lookup`, `_shell_config_names`
   and `_shell_config_list` from `00-shell-config.zsh`, at call time, never hardcoded.
   Add `config/<name>.conf.example` with placeholder entries — the repo is public.
3. Register completion only `if (( $+functions[compdef] ))`, so the file also loads,
   without an error status, where `compinit` has not run.
4. `./sync.sh`, open a new shell.

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
  files from your `.zshrc` yourself, `00-shell-config.zsh` first.
- **Conf dir:** `$SHELL_CONFIG_HOME`, else `${XDG_CONFIG_HOME:-~/.config}/shell-config`.
  The helpers read it at call time, so it must be set before you call them.

### Files

Each `zsh/*.zsh` is copied as is. `$ZSH_CUSTOM/.gokselkoksal-shell-config.manifest`
lists the files sync put there, and those are the only ones it overwrites or removes: a
file deleted or renamed here is removed there. Anything not in the manifest — your own
`*.zsh`, oh-my-zsh's `plugins/` and `themes/` — is never modified or deleted.

`00-shell-config.zsh` is the shared part: the dispatcher and the conf-file reader. The
`00-` makes oh-my-zsh, which loads `custom/*.zsh` alphabetically, load it before the
helpers that use it at load time.

### Conf files

One `<helper>.conf` per helper, one entry per line: a name, whitespace, then the value to
the end of the line. Blank lines and `#` lines are skipped. In the value a leading `~/`
and `$VARIABLES` are expanded; an entry with `$(…)` or backticks is skipped with a
warning, so the file cannot run anything. It is still trusted like `.zshrc` for what it
points at.

```
# goto.conf
docs   ~/Documents
repos  $HOME/Development/Repos
```

Sync rewrites the `.example` files on every run and logs a hint for each `.conf` that is
missing. It never writes a `.conf`.

### When sync refuses

Everything is checked before anything is written. Any of these fails the run with the
full list, leaving every destination as it was:

- a repo file's name is already taken in `custom/` by something not in the manifest —
  the hand-copied version of the same helper, usually; move it away;
- a managed file has become a symlink or a directory, whether it is still in the repo or
  has left it;
- the custom dir does not exist and neither does its parent (no oh-my-zsh) — install it
  or set `ZSH_CUSTOM`;
- the custom dir, the conf dir, or any folder above either is a plain file or a symlink
  to nothing (a symlink to a directory is fine);
- a `.conf.example` in the conf dir is a symlink or not a regular file.

A file renamed here only in case (`goto.zsh` → `Goto.zsh`) is recognised as the same
file on a case-insensitive filesystem and just re-recorded under the new name.

## Git hooks

`bootstrap.sh` installs `git-hooks/pre-push` and `git-hooks/post-merge` into the hooks
directory git uses. Both fire only for the default branch:

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
when `zsh/`, `config/` or `sync.sh` has uncommitted changes. An untracked file anywhere
else in the checkout does not stop them.

Both hooks run `sync.sh`, never `bootstrap.sh`: publishing should sync, not re-check
prerequisites. So a change to `git-hooks/` lands only when you run `./bootstrap.sh`
again — committing it is not enough.

A pre-existing hook that didn't come from this repo is left alone with a warning, and is
never removed. With `core.hooksPath` set, git never reads `.git/hooks`, so bootstrap
installs nothing and says so rather than report success for hooks that would not run.
