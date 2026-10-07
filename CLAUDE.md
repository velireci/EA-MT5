# Claude Code entry point

@AGENTS.md

- Default role: implement the current assigned task and maintain docs/STATE.md.
- Read task scope before deciding to use a subagent. Do not run all agents for every request.
- Optional project agents: evidence-reader, mql5-builder, strategy-reviewer. Give each a bounded request and relevant file paths.
- The parent agent integrates findings and updates shared state; read-only agents return concise findings.
- Model aliases in .claude/agents/ are suggested routing choices. Verify availability and actual selected model in this installation; they do not guarantee capability, pricing or lower total token use.
- Keep detailed documents as ordinary file references. Do not import the entire strategy, raw answers or reports into this file.
