---
status: accepted
---

# Ship CLI Workflows as Skill References

Keep detailed agent workflows as regular files inside `.agents/skills/den/references/`, with `web.md` covering `den board web`. `SKILL.md` holds the entry guidance and links to references when needed; `docs/cli.md` remains the CLI specification and links to the same workflow files for public readers.

Bundling references keeps the skill usable without fetching documentation over the network and installs its guidance together. A symlink to a document outside the skill directory can be copied successfully, but changes to its target may escape skill-directory update detection: `skills@1.7.2` dereferences links during Git-based installation and uses the skill directory's Git tree hash for GitHub update tracking. Keep the workflow files themselves in the skill directory rather than depending on external symlink targets or maintaining duplicate copies.

Sources: [skills installer](https://github.com/vercel-labs/skills/blob/main/src/installer.ts), [skills update tracking](https://github.com/vercel-labs/skills/blob/main/src/skill-lock.ts).
