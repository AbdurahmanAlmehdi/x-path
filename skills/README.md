# Agent skills for XPath

Skills in the open [Agent Skills](https://agentskills.io) format, for agents that use or change
XPath. Each folder holds a `SKILL.md` and, where the detail would bloat it, `references/`.

| Skill | Use it to |
|---|---|
| [`xpath-release`](xpath-release/SKILL.md) | Operate XPath through `xp` and `xp mcp`: dispatch dev builds, production releases and Shorebird patches, follow runs and logs, read releases and store lanes. Never approves a gate. |
| [`xpath-workflows`](xpath-workflows/SKILL.md) | Write, copy and validate workflow YAML (schema 1): stages, jobs, matrix, expressions, gates, inputs and step kinds. |
| [`xpath-setup`](xpath-setup/SKILL.md) | Install XPath (macOS, Linux, Docker), make device tokens, connect GitHub, add credentials, pair runners, check health and troubleshoot. |
| [`xpath-contributing`](xpath-contributing/SKILL.md) | Change XPath itself: layer rules, tests and coverage, the local gate, migrations, API contracts, the desktop app, pull request titles. |

Install them with the [`skills`](https://www.npmjs.com/package/skills) CLI:

```sh
npx skills add AbdurahmanAlmehdi/x-path                          # pick skills and agents
npx skills add AbdurahmanAlmehdi/x-path --list                   # list the skills
npx skills add AbdurahmanAlmehdi/x-path --skill xpath-release -a claude-code
```
