#!/bin/sh
# Builds a made-up home folder in build/test-home, with skills and chats for testing
# adding, uninstalling, renaming, editing and merging. Prints its path.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
H="$ROOT/build/test-home"
rm -rf "$H"
for d in .cursor .claude .codex .gemini .config/opencode .local/share/opencode .factory .pi/agent .config/amp; do mkdir -p "$H/$d"; done
mkdir -p "$H/.agents/skills" "$H/.claude/skills" "$H/.cursor/skills" "$H/.pi/agent/skills" "$H/projects/skills"

skill() { # folder name description body
  mkdir -p "$1"
  printf -- '---\nname: %s\ndescription: %s\n---\n\n%s\n' "$2" "$3" "$4" > "$1/SKILL.md"
}

skill "$H/.agents/skills/writing-style" writing-style \
  "Write docs, READMEs and blog posts in my voice: short sentences, a friendly tone and real examples. Use for any writing task." \
  "# Writing style

- Write short sentences, 8 to 15 words.
- Use a friendly, direct tone. Talk to the reader as you.
- Use real examples, never placeholder names.
- Read references/tone.md for the words to avoid.
- See examples/blog.md for a finished post."
mkdir -p "$H/.agents/skills/writing-style/references" "$H/.agents/skills/writing-style/examples"
echo "Avoid: basically, simply, leverage." > "$H/.agents/skills/writing-style/references/tone.md"
echo "A finished blog post." > "$H/.agents/skills/writing-style/examples/blog.md"
ln -s "$H/.agents/skills/writing-style" "$H/.claude/skills/writing-style"

skill "$H/.claude/skills/email-style" email-style \
  "Write newsletter emails in my voice: short sentences, a friendly tone, one idea per email. Use for any email or newsletter." \
  "# Email style

- Write short sentences and short paragraphs.
- Use a friendly, direct tone. Talk to the reader as you.
- One idea per email, with a clear subject line.
- Start from templates/newsletter.md.
- Read references/tone.md for the words to avoid."
mkdir -p "$H/.claude/skills/email-style/templates" "$H/.claude/skills/email-style/references"
echo "Hi {name}," > "$H/.claude/skills/email-style/templates/newsletter.md"
echo "Avoid: hope this finds you well." > "$H/.claude/skills/email-style/references/tone.md"
cp -R "$H/.claude/skills/email-style" "$H/.pi/agent/skills/email-style"

skill "$H/projects/skills/release-notes" release-notes \
  "Turn the commits since the last tag into release notes, grouped into features and fixes." \
  "# Release notes

1. Run git log since the last tag.
2. Group the commits into features and fixes."
ln -s "$H/projects/skills/release-notes" "$H/.agents/skills/release-notes"
ln -s "../../projects/skills/release-notes" "$H/.cursor/skills/release-notes"

skill "$H/.agents/skills/commit-and-push" commit-and-push \
  "Commit the current work with a clear message and push it to the current branch." \
  "# Commit and push

Commit with a clear message, then push. Never force push."
P="$H/.cursor/plugins/cache/acme/commit-tools/1.0.0"
mkdir -p "$P/.cursor-plugin"
echo '{"name":"commit-tools"}' > "$P/.cursor-plugin/plugin.json"
skill "$P/skills/commit-and-push" commit-and-push "Commit and push, from the commit-tools plugin." "Commit and push."

skill "$H/.agents/skills/sql-migration" sql-migration "Write a reversible Postgres migration, run it locally, and update the schema notes." "Write the up and down SQL, run it, update docs/schema.md."
skill "$H/.agents/skills/cloudflare-deploy" cloudflare-deploy "Deploy the project to Cloudflare Workers with wrangler, then tail the logs." "Run wrangler deploy, then wrangler tail."
skill "$H/.cursor/skills/swiftui-previews" swiftui-previews "Add SwiftUI previews with realistic sample data for the views I'm working on." "Add a #Preview with sample data."
skill "$H/.agents/skills/test-first" test-first "Reproduce a bug with a failing test first, then fix it and show both test runs." "Write the failing test, fix the bug, run the tests again."
skill "$H/.agents/skills/perf-audit" perf-audit "Measure Core Web Vitals for a page and list the three fixes with the biggest impact." "Run Lighthouse, read LCP, INP and CLS, list three fixes."

# Claude Code chats that used release-notes, writing-style and email-style.
C="$H/.claude/projects/-Users-demo-blog"
mkdir -p "$C"
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
use() { # session tool-input
  printf '{"type":"assistant","timestamp":"%s","cwd":"/Users/demo/blog","sessionId":"%s","message":{"role":"assistant","content":[{"type":"tool_use","name":"%s","input":%s}]}}\n' "$now" "$1" "$2" "$3" >> "$C/$1.jsonl"
}
use s1 Read "{\"file_path\":\"$H/.agents/skills/release-notes/SKILL.md\"}"
use s2 Read "{\"file_path\":\"$H/.agents/skills/release-notes/SKILL.md\"}"
use s3 Skill '{"skill":"email-style"}'
use s4 Skill '{"skill":"email-style"}'
use s5 Skill '{"skill":"email-style"}'
use s6 Read "{\"file_path\":\"$H/.agents/skills/writing-style/SKILL.md\"}"
echo "$H"
