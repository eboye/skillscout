#!/usr/bin/env bash
# Builds a made-up home in build/demo-home, with skills, chats, a saved idea and a fake Codex CLI,
# for screenshots and tests. Never touches the real home.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
home="$root/build/demo-home"
rm -rf "$home"

skill() {
  local folder="$1" name="$2" description="$3" body="$4"
  mkdir -p "$folder/$name"
  printf -- '---\nname: %s\ndescription: %s\n---\n\n%s\n' "$name" "$description" "$body" > "$folder/$name/SKILL.md"
}

skill "$home/.agents/skills" release-notes "Turn the commits since the last tag into release notes, grouped into features and fixes." "Run git log since the last tag, group commits into features and fixes, and write plain-language notes."
skill "$home/.agents/skills" commit-and-push "Commit the current work with a clear message and push it." "Stage the changes, write a short commit message, and push to the current branch."
skill "$home/.claude/skills" code-review "Review the current diff for bugs, missing tests and unclear names." "Read the diff, look for bugs, missing tests and unclear names, and list them by severity."
skill "$home/.claude/skills" writing-style "Write in a short, friendly tone with plain sentences." "Use short sentences, a friendly tone, and plain words. Avoid jargon."
skill "$home/.codex/skills" email-style "Write emails in a short, friendly tone with plain sentences." "Use short sentences, a friendly tone, plain words, and a clear ask at the end of every email."
skill "$home/.cursor/skills" pdf-invoices "Generate PDF invoices from a JSON order." "Read the JSON order, fill the invoice template, and render it to PDF."

mkdir -p "$home/.gemini" "$home/.config/opencode"
ln -s "$home/.agents/skills/release-notes" "$home/.claude/skills/release-notes"

# One Claude Code chat that loads code-review, and a typed prompt in history.
mkdir -p "$home/.claude/projects/-demo-shop"
now="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
ms="$(($(date +%s) * 1000))"
printf '{"type":"assistant","sessionId":"demo-1","cwd":"/demo/shop","timestamp":"%s","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"code-review"}}]}}\n' "$now" > "$home/.claude/projects/-demo-shop/demo-1.jsonl"
{
  printf '{"display":"check the links before deploying the site","timestamp":%s,"project":"/demo/shop"}\n' "$ms"
  printf '{"display":"bump the version and tag the release please","timestamp":%s,"project":"/demo/shop"}\n' "$((ms - 3600000))"
  printf '{"display":"bump the version number and tag it for release","timestamp":%s,"project":"/demo/blog"}\n' "$((ms - 7200000))"
  printf '{"display":"can you bump the version and create the release tag","timestamp":%s,"project":"/demo/docs"}\n' "$((ms - 10800000))"
} > "$home/.claude/history.jsonl"

# A fake Codex CLI, first on the login shell's PATH, so the AI features run without a network or an account.
mkdir -p "$home/fakebin"
cp "$root/Linux/scripts/fake-codex.sh" "$home/fakebin/codex"
chmod +x "$home/fakebin/codex"
printf 'export PATH="$HOME/fakebin:$PATH"\n' > "$home/.bash_profile"

# A saved skill idea with a draft, in the app's state.json. Dates count seconds from 2001.
mkdir -p "$home/.local/share/skillscout"
ref="$(($(date +%s) - 978307200))"
draft='---\nname: link-check\ndescription: Check every link on the site before deploying.\n---\n\nRun the link checker on the built site, list the broken links, and stop the deploy if there are any.\n'
printf '{"suggestions":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"link-check","title":"Check links before deploying","summary":"Run a link check on the built site and stop the deploy when a link is broken.","why":"You asked for this before three deploys in two projects.","examples":[{"id":"a1","tool":"claude","project":"shop","date":%s,"text":"check the links before deploying the site"},{"id":"a2","tool":"codex","project":"blog","date":%s,"text":"can you make sure no links are broken before we deploy?"},{"id":"a3","tool":"cursor","project":"blog","date":%s,"text":"run a link check, then deploy if it passes"}],"createdAt":%s,"draft":"%s"}],"dismissed":[],"explanations":{},"analyzedIDs":[],"lastAnalysis":%s,"dismissedPairs":[]}\n' \
  "$ref" "$((ref - 86400))" "$((ref - 172800))" "$ref" "$draft" "$ref" > "$home/.local/share/skillscout/state.json"

echo "$home"
