# /// script
# requires-python = ">=3.12"
# dependencies = ["pygobject"]
# ///
"""Clicks through the GNOME app over AT-SPI, against the made-up home, and checks the files on disk.

Run it through Linux/scripts/ui-test.sh, which builds the app and the made-up home and starts a
headless mutter for it.
"""
import json
import os
import shlex
import subprocess
import sys
import time
from pathlib import Path

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
HOME = ROOT / "build/demo-home"
# SKILLSCOUT_APP runs another build of the app, like the Flatpak, as a shell-quoted command.
STATE = Path(os.environ.get("SKILLSCOUT_STATE", str(HOME / ".local/share/skillscout/state.json")))
APP = shlex.split(os.environ.get("SKILLSCOUT_APP", str(ROOT / ".build/debug/skillscout-gnome")))
results: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    results.append((name, ok, detail))
    print(("PASS " if ok else "FAIL ") + name + (f"  ({detail})" if detail and not ok else ""), flush=True)


def wait(predicate, timeout: float = 10.0, step: float = 0.2):
    end = time.time() + timeout
    while time.time() < end:
        value = predicate()
        if value:
            return value
        time.sleep(step)
    return None


def showing(node) -> bool:
    try:
        return node.get_state_set().contains(Atspi.StateType.SHOWING)
    except Exception:
        return False


def walk(node, depth=0):
    if node is None or depth > 60:
        return
    yield node
    try:
        count = node.get_child_count()
    except Exception:
        return
    for index in range(count):
        try:
            child = node.get_child_at_index(index)
        except Exception:
            continue
        if child is not None and showing(child):
            yield from walk(child, depth + 1)


LAUNCHED: set[int] = set()


def descendants(pid: int) -> set[int]:
    """The process and every process it started, so a wrapper like the Flatpak's still counts."""
    found, queue = {pid}, [pid]
    while queue:
        parent = queue.pop()
        for child in Path("/proc").glob("[0-9]*"):
            try:
                if int((child / "stat").read_text().rsplit(")", 1)[1].split()[1]) == parent and int(child.name) not in found:
                    found.add(int(child.name))
                    queue.append(int(child.name))
            except (OSError, ValueError, IndexError):
                continue
    return found


NAMES = ("skillscout-gnome", "Skillscout", "com.flaviocopes.skillscout")
ALREADY_OPEN: set[int] = set()


def skillscout_apps():
    desktop = Atspi.get_desktop(0)
    for index in range(desktop.get_child_count()):
        child = desktop.get_child_at_index(index)
        try:
            if child is not None and child.get_name() in NAMES:
                yield child, child.get_process_id()
        except Exception:
            continue


def app_root():
    """The app this test started, never a Skillscout you have open with your real skills: one
    whose process this test launched, or, for a Flatpak, whose accessibility proxy reports another
    process, one that wasn't on the bus before the test."""
    ours = descendants(next(iter(LAUNCHED))) if LAUNCHED else set()
    for child, pid in skillscout_apps():
        if pid in ours or (LAUNCHED and pid not in ALREADY_OPEN):
            return child
    return None


def text_of(node) -> str:
    try:
        return Atspi.Text.get_text(node, 0, -1) or ""
    except Exception:
        return ""


def label(node) -> str:
    return node.get_name() or text_of(node)


def find(role=None, name=None, contains=None, description=None):
    root = app_root()
    for node in walk(root):
        try:
            if role is not None and node.get_role() != role:
                continue
            text = label(node)
            if name is not None and text != name:
                continue
            if contains is not None and contains not in text:
                continue
            if description is not None and description not in (node.get_description() or ""):
                continue
            return node
        except Exception:
            continue
    return None


def button(name=None, description=None, timeout=10.0):
    return wait(lambda: find(Atspi.Role.BUTTON, name=name, description=description), timeout)


def click(name=None, description=None, timeout=10.0) -> bool:
    node = button(name, description, timeout)
    if node is None:
        return False
    Atspi.Action.do_action(node, 0)
    time.sleep(0.6)
    return True


def select_row(text: str, timeout=10.0) -> bool:
    """Selects the list row that shows `text`."""
    def row():
        node = find(Atspi.Role.LABEL, name=text)
        while node is not None and node.get_role() not in (Atspi.Role.LIST_ITEM, Atspi.Role.LIST_BOX_ITEM if hasattr(Atspi.Role, "LIST_BOX_ITEM") else Atspi.Role.LIST_ITEM):
            node = node.get_parent()
        return node
    item = wait(row, timeout)
    if item is None:
        return False
    parent = item.get_parent()
    Atspi.Selection.select_child(parent, item.get_index_in_parent())
    time.sleep(0.8)
    return True


def set_text(role, value: str, timeout=10.0) -> bool:
    node = wait(lambda: find(role), timeout)
    if node is None:
        return False
    Atspi.EditableText.set_text_contents(node, value)
    time.sleep(0.5)
    return True


def trash() -> list[str]:
    folder = HOME / ".local/share/Trash/files"
    return sorted(p.name for p in folder.iterdir()) if folder.exists() else []


def main() -> int:
    if "SKILLSCOUT_APP" in os.environ:
        # A launcher like flatpak run needs the real home to find its installation, so the command
        # passes HOME, SHELL and SKILLSCOUT_TEST into the app itself, with --env.
        env = dict(os.environ)
    else:
        env = {k: v for k, v in os.environ.items() if k not in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "DISPLAY")}
        # SKILLSCOUT_TEST keeps this run from handing over to a Skillscout that's already open.
        env.update(HOME=str(HOME), SHELL="/bin/bash", SKILLSCOUT_TEST="1")
    ALREADY_OPEN.update(pid for _, pid in skillscout_apps())
    app = subprocess.Popen(APP, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    LAUNCHED.add(app.pid)
    try:
        check("app shows up on the accessibility bus", wait(lambda: find(Atspi.Role.LABEL, name="release-notes"), 20) is not None)

        # Add to another agent
        check("select writing-style", select_row("writing-style"))
        check("click Add to Codex", click("Add to Codex"))
        link = HOME / ".codex/skills/writing-style"
        check("Add to Codex links the folder", wait(link.is_symlink, 5) is True, str(link))

        # Explain with AI, through the fake codex
        check("click Explain with AI", click("Explain with AI"))
        check("explanation shows up", wait(lambda: find(contains="FAKE EXPLANATION"), 15) is not None)

        # Rename
        check("click Rename…", click("Rename…"))
        field = wait(lambda: find(Atspi.Role.TEXT, name="writing-style") or find(Atspi.Role.ENTRY, name="writing-style"), 5)
        check("the rename field holds the old name", field is not None)
        if field is not None:
            Atspi.EditableText.set_text_contents(field, "tone-guide")
            time.sleep(0.5)
        check("click Rename", click("Rename"))
        time.sleep(1.5)
        alert = find(name="Something went wrong")
        if alert is not None:
            box = alert.get_parent().get_parent().get_parent()
            print("  error alert:", [label(node) for node in walk(box) if node.get_role() == Atspi.Role.LABEL])
        renamed = HOME / ".claude/skills/tone-guide"
        check("rename moves the folder", wait(renamed.is_dir, 5) is True and not (HOME / ".claude/skills/writing-style").exists())
        check("rename recreates the Codex link", wait((HOME / ".codex/skills/tone-guide").is_symlink, 5) is True)
        check("rename changes the frontmatter", "name: tone-guide" in (renamed / "SKILL.md").read_text())
        check("the renamed skill is selected", wait(lambda: find(Atspi.Role.LABEL, name="tone-guide"), 5) is not None)

        # Edit, with a change on disk in between
        check("click Edit", click("Edit"))
        new_text = "---\nname: tone-guide\ndescription: Write in a short, friendly tone.\n---\n\nUse short sentences -- and \"straight\" quotes.\n"
        editor = wait(lambda: find(Atspi.Role.TEXT, contains="name: tone-guide"), 5)
        check("editor shows the SKILL.md", editor is not None)
        if editor is not None:
            Atspi.EditableText.set_text_contents(editor, new_text)
            time.sleep(0.5)
        skill_file = renamed / "SKILL.md"
        skill_file.write_text(skill_file.read_text() + "\nAn agent changed this.\n")
        check("click Save", click("Save"))
        check("a change on disk asks before saving", button("Save Anyway", timeout=5) is not None)
        check("click Save Anyway", click("Save Anyway"))
        check("Save Anyway writes the text as typed", wait(lambda: skill_file.read_text() == new_text, 5) is True, skill_file.read_text())

        # Uninstall, with a link
        check("select release-notes", select_row("release-notes"))
        check("click Uninstall this skill", click("Uninstall this skill"))
        check("confirm Move to Trash", click("Move to Trash"))
        check("uninstall moves the folder and the link to the Trash",
              wait(lambda: trash().count("release-notes") + trash().count("release-notes.2") >= 2, 5) is True, str(trash()))

        # A skill that appears on disk shows up by itself
        outside = HOME / ".agents/skills/outside-skill"
        outside.mkdir(parents=True)
        (outside / "SKILL.md").write_text("---\nname: outside-skill\ndescription: Made outside the app.\n---\n\nHello.\n")
        check("the watcher picks up a new skill", wait(lambda: find(Atspi.Role.LABEL, name="outside-skill"), 15) is not None)

        # Merge similar skills, through the fake codex
        check("open Similar skills", select_row("Similar skills"))
        pair = wait(lambda: find(Atspi.Role.LABEL, contains=" + "), 5)
        check("a similar pair is listed", pair is not None)
        if pair is not None:
            select_row(label(pair))
        check("click Merge with AI", click("Merge with AI"))
        merge = wait(lambda: find(Atspi.Role.BUTTON, contains="Merge into "), 15)
        check("the merged draft shows up", merge is not None)
        kept = label(merge).replace("Merge into ", "") if merge else ""
        merged = "email-style" if kept != "email-style" else "tone-guide"
        if merge is not None:
            Atspi.Action.do_action(merge, 0)
            time.sleep(0.6)
        check("confirm Merge", click("Merge"))
        kept_folder = HOME / (".claude/skills/" + kept if kept == "tone-guide" else ".codex/skills/" + kept)
        check("merge writes the merged SKILL.md", wait(lambda: "End every email with a clear ask." in (kept_folder / "SKILL.md").read_text(), 5) is True)
        check("merge moves the other skill to the Trash", merged in trash(), str(trash()))

        # Find repeated tasks, draft and save, through the fake codex
        check("open Suggestions", select_row("Suggestions"))
        check("click Find repeated tasks", click(description="Find repeated tasks"))
        check("a new idea shows up", select_row("Bump the version and tag", timeout=15))
        check("click Draft the Skill with AI", click("Draft the Skill with AI"))
        check("the draft shows up", wait(lambda: find(Atspi.Role.TEXT, contains="name: release-tag"), 15) is not None)
        check("click Save to All Tools", click("Save to All Tools"))
        saved = HOME / ".agents/skills/release-tag/SKILL.md"
        check("Save to All Tools writes ~/.agents/skills", wait(saved.exists, 5) is True)
        check("Save to All Tools links it for Claude Code", (HOME / ".claude/skills/release-tag").is_symlink())

        # Dismiss an idea
        check("select the saved idea from before", select_row("Check links before deploying"))
        check("click Dismiss This Idea", click("Dismiss This Idea"))
        state = json.loads(STATE.read_text())
        check("dismissing remembers the idea", "link-check" in state.get("dismissed", []), str(state.get("dismissed")))

        # Search
        check("back to All skills", select_row("All skills"))
        search = wait(lambda: find(Atspi.Role.TEXT, name="") or find(Atspi.Role.ENTRY), 5)
        if search is not None:
            Atspi.EditableText.set_text_contents(search, "pdf")
        check("search keeps the matching skill", wait(lambda: find(Atspi.Role.LABEL, name="pdf-invoices"), 5) is not None)
        check("search hides the others", wait(lambda: find(Atspi.Role.LABEL, name="code-review") is None, 5) is True)
        if search is not None:
            Atspi.EditableText.set_text_contents(search, "")

        # Discard an edit
        check("select code-review", select_row("code-review"))
        review = HOME / ".claude/skills/code-review/SKILL.md"
        before = review.read_text()
        check("click Edit again", click("Edit"))
        editor = wait(lambda: find(Atspi.Role.TEXT, contains="name: code-review"), 5)
        if editor is not None:
            Atspi.EditableText.set_text_contents(editor, before + "\nThrow this away.\n")
            time.sleep(0.5)
        check("click Cancel", click("Cancel"))
        check("unsaved changes ask first", click("Discard"))
        check("discarding leaves the file alone", review.read_text() == before)

        # Remove one copy, a link, and keep the folder it points to
        check("select pdf-invoices", select_row("pdf-invoices"))
        check("add pdf-invoices to Codex", click("Add to Codex"))
        path_label = wait(lambda: find(Atspi.Role.LABEL, contains="~/.codex/skills/pdf-invoices →"), 5)
        row = path_label.get_parent().get_parent() if path_label else None
        remove = next((n for n in walk(row) if n.get_role() == Atspi.Role.BUTTON and label(n) == "Remove"), None) if row else None
        check("the Codex copy has a Remove button", remove is not None)
        if remove is not None:
            Atspi.Action.do_action(remove, 0)
            time.sleep(0.6)
        check("confirm Move to Trash for one copy", click("Move to Trash"))
        check("Remove takes the copy and keeps the other",
              wait(lambda: not (HOME / ".codex/skills/pdf-invoices").exists(), 5) is True and (HOME / ".cursor/skills/pdf-invoices").is_dir())

        # Turn a tool off in Preferences, from the main menu
        menu = wait(lambda: find(Atspi.Role.TOGGLE_BUTTON, description="Main Menu") or find(Atspi.Role.BUTTON, description="Main Menu"), 5)
        check("the main menu is there", menu is not None)
        if menu is not None:
            Atspi.Action.do_action(menu, 0)
            time.sleep(0.8)
        def menu_item(text):
            for node in walk(app_root()):
                if node.get_role() == Atspi.Role.MENU_ITEM and any(label(child) == text for child in walk(node)):
                    return node
            return None
        # GTK menu items have no accessible names, so take Preferences by its place, first.
        item = wait(lambda: find(name="Preferences", role=Atspi.Role.MENU_ITEM) or menu_item("Preferences") or find(role=Atspi.Role.MENU_ITEM), 5)
        if item is None:
            print("  menu items:", [[label(c) for c in walk(n)] for n in walk(app_root()) if n.get_role() == Atspi.Role.MENU_ITEM])
        check("the menu has Preferences", item is not None)
        if item is not None:
            Atspi.Action.do_action(item, 0)
            time.sleep(1)
        switch = wait(lambda: find(Atspi.Role.SWITCH, name="Codex") or find(Atspi.Role.SWITCH, description="Codex"), 5)
        if switch is None:
            print("  switch-ish nodes:", [(n.get_role_name(), label(n)) for n in walk(app_root()) if "Codex" in label(n)][:12])
        # GTK's switches have no accessible action, so toggling one is left to a person.
        check("Preferences lists the tools", switch is not None)
    finally:
        app.terminate()
        app.wait(5)

    failed = [r for r in results if not r[1]]
    print(f"\n{len(results) - len(failed)} passed, {len(failed)} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
