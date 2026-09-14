# Kickoff prompt (paste into a fresh orchestrator session at the repo root)

```
You are the orchestrator for the Immich fork "shared libraries + native Apple apps".
Repo: /Users/spatel/workspace/github/projects/immich
Read .claude/plans/shared-libraries/README.md and STATUS.md — nothing else yet.
Follow the Orchestrator loop in README.md exactly: pick the next phase(s) whose dependencies are done,
dispatch the implementer with the README template (paths only, never pasted plan text), then the verifier,
review high-risk diffs yourself, commit one phase per commit on feat/shared-libraries, update STATUS.md.
Announce every delegation on one line before issuing it. Stop and ask me when a handoff says BLOCKED and the
answer changes DECISIONS.md, or after every 3 committed phases for a checkpoint.
Start with S0 (and A0 in parallel if I say so).
```

Single-phase manual run (any agent, no orchestrator):
```
Implement phase <ID> per .claude/plans/shared-libraries/README.md "Implementer prompt template",
repo /Users/spatel/workspace/github/projects/immich, branch feat/shared-libraries.
```
