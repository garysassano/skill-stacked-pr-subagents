# Working in skill-stacked-pr-subagents

This repository holds one agent skill, `.agents/skills/stacked-pr-subagents/`, and a README that explains its strategy with Mermaid diagrams. It is public: examples use made-up branch names, PR numbers and ids.

`references/harnesses.md` records how each harness spawns, identifies and resumes subagents, checked on the date and versions it names. Before changing a claim there, verify it against the harness's current docs, changelog or source, cite the source, and update the date and versions. Keep the README's harness table in step with it.

Keep `SKILL.md` harness-neutral; harness details belong in `references/harnesses.md`. Keep the README's diagrams consistent with the procedure in `SKILL.md`.

Run `prettier --check .` and `markdownlint-cli2 "**/*.md"` (or `markdownlint "**/*.md"`) on Markdown, and `shellcheck` and `shfmt -d` on `scripts/`. Render changed Mermaid diagrams before committing, for example with `npx -y @mermaid-js/mermaid-cli -i README.md -o /tmp/out.md`.
