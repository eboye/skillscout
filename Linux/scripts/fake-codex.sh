#!/usr/bin/env bash
# Stands in for `codex exec ... -o <file> -` in tests: reads the prompt on stdin and writes a canned
# reply to the -o file, shaped like the one Analyzer.swift asks for.
set -euo pipefail

out=""
while [ $# -gt 0 ]; do
  if [ "$1" = "-o" ]; then out="$2"; shift; fi
  shift
done
prompt="$(cat)"
name="$(printf '%s\n' "$prompt" | sed -n 's/^ *name: \([a-z0-9-]*\)$/\1/p' | head -1)"
sleep 1

if [[ "$prompt" == *"Merge two Agent Skills"* ]]; then
  reply="$(printf -- '---\nname: %s\ndescription: Write emails and other text in a short, friendly tone with plain sentences.\n---\n\nUse short sentences, a friendly tone and plain words.\nEnd every email with a clear ask.\n' "$name")"
elif [[ "$prompt" == *"Explain the Agent Skill"* ]]; then
  reply="FAKE EXPLANATION: this skill tells the agent how to do the task, and needs nothing else to work."
elif [[ "$prompt" == *"Find up to 10 skill ideas"* ]]; then
  reply='{"suggestions":[{"name":"release-tag","title":"Bump the version and tag","summary":"Bump the version number and create the release tag.","why":"You asked for this in three projects.","messageIds":[2,3,4]}]}'
elif [[ "$prompt" == *"Write a SKILL.md file"* ]]; then
  reply="$(printf -- '---\nname: %s\ndescription: Bump the version and tag the release.\n---\n\n# Release tag\n\n1. Bump the version.\n2. Tag the release.\n' "$name")"
else
  reply="unexpected prompt"
fi

if [ -n "$out" ]; then printf '%s\n' "$reply" > "$out"; fi
printf '%s\n' "$reply"
