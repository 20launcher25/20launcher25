# Claude Code Launcher usage policy

[Русский](POLICY.md) · [Қазақша](POLICY.kk.md) · **English**

*Effective November 23, 2026.*

## 1. What it is

Claude Code Launcher is a free menu for starting [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) on Windows, maintained by the [20launcher25](https://github.com/20launcher25) organization.

It is an **unofficial** project: Anthropic did not make, review or support it. "Claude" and "Claude Code" are Anthropic trademarks, used here only to name the program the launcher works with.

## 2. Terms of use

- The launcher is free to use, at home and at work.
- Using Claude Code through the launcher is still using Claude Code, so [Anthropic's terms](https://www.anthropic.com/legal) and [usage policy](https://www.anthropic.com/legal/aup) apply. The launcher neither changes nor bypasses them. It only shows subscription limits and never raises them.
- Do not use the launcher or its skills for anything that breaks the law or Anthropic's rules.
- Share the launcher by linking to this repository. Do not present modified copies as the official 20launcher25 version or distribute them under the same name.

## 3. What data it uses

The launcher runs on your computer and **sends nothing about you**. It has no analytics and no telemetry.

| What | Why | Where it goes |
| --- | --- | --- |
| Claude Code session history (`~/.claude/projects`) | list of recent projects and sessions | nowhere, read only |
| Account data from `~/.claude.json` (name, email, plan) | the Info and limits screen | nowhere, read only |
| Subscription limits (written by the `usage-mod` mod) | limit bars | nowhere |
| Launcher settings (`%LOCALAPPDATA%\ClaudeCodeLauncher`) | your settings | nowhere |

The launcher goes online only by itself and only here: it downloads `manifest.json`, updates and skills from this repository (`raw.githubusercontent.com`). Like any website, GitHub sees your IP address. Automatic checks can be turned off in Settings → Check on startup.

## 4. Updates and skills

- Every update or skill file is checked against the SHA-256 checksum in `manifest.json` before it is installed. The launcher cannot write files outside its own folder or the skill's folder.
- Skills in the catalog are instructions for Claude. Installing one lets Claude use them, so read the description first.
- Only maintainers change the repository. Contributions from others are accepted through reviewed pull requests (section 6).

## 5. Liability

The program is provided **"as is"**, without warranty. The maintainers are not liable for data loss, used-up subscription limits or the results of actions taken by Claude started from the launcher. Modes that let Claude act without asking ("auto-accept edits", "auto") are turned on at your own risk.

## 6. Proposing changes and reporting problems

- Send bugs and ideas to [Issues](https://github.com/20launcher25/20launcher25/issues). Attach the report from Settings → Component check → Copy report. It contains only versions and file paths, but read it before sending anyway.
- Propose code or skills through a fork and a pull request. It reaches `main` only after a maintainer approves it.
- Do not report vulnerabilities in public issues. Use [Security → Report a vulnerability](https://github.com/20launcher25/20launcher25/security).

## 7. Policy changes

New versions are published in this file, and every edit is visible in the commit history. Continuing to use the launcher after a change means you accept the new version.
