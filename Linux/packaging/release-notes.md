Skillscout @VERSION@ for Linux: the GNOME app and the `skillscout` command, a fork of [Skill Cabinet](https://flaviocopes.com/skill-cabinet/) 1.5.0 by Flavio Copes.

The Flatpak and the AppImage bring GTK 4 and libadwaita with them. The other packages need libadwaita 1.8 or later from your distribution, so GNOME 49 or a distribution as recent. They all include the Swift runtime.

| Package | For | Install |
| --- | --- | --- |
| `skillscout_@VERSION@-@RELEASE@_amd64.deb` | Ubuntu 26.04 and later, Debian testing | `sudo apt install ./skillscout_@VERSION@-@RELEASE@_amd64.deb` |
| `skillscout-@VERSION@-@RELEASE@.x86_64.rpm` | Fedora 44 and later | `sudo dnf install ./skillscout-@VERSION@-@RELEASE@.x86_64.rpm` |
| `skillscout-@VERSION@-@RELEASE@-x86_64.pkg.tar.zst` | Arch Linux and derivatives | `sudo pacman -U skillscout-@VERSION@-@RELEASE@-x86_64.pkg.tar.zst` |
| `skillscout-@VERSION@.flatpak` | Any distribution with Flatpak | `flatpak install --user skillscout-@VERSION@.flatpak` |
| `Skillscout-@VERSION@-x86_64.AppImage` | Any distribution with glibc 2.43 or later | `chmod +x Skillscout-@VERSION@-x86_64.AppImage`, then run it |
| `skillscout-@VERSION@-linux-x86_64.tar.gz` | Anything else with libadwaita 1.8 and glibc 2.43 | `tar -xzf skillscout-@VERSION@-linux-x86_64.tar.gz && cp -r skillscout-@VERSION@-linux-x86_64/{bin,lib,share} ~/.local/` |

The Flatpak has your home folder, since the agents keep their skills there. It runs the Codex and Claude Code CLIs on your system, outside the sandbox, so the AI features work as they do elsewhere. Its **Install Command Line Tool** puts a `skillscout` script in `~/.local/bin` that runs the command from the Flatpak.

Coming from Skill Cabinet for Linux? Skillscout is the same app under a new name and app ID, `io.github.eboye.skillscout`. The Flatpak installs next to the old one and copies your settings and data on its first start, then you can remove the old one with `flatpak uninstall com.flaviocopes.skillscout`. The other packages replace it.

There's no automatic update check on Linux. Install a newer package the same way, or update the Flatpak with `flatpak update`.

Check the downloads against `SHA256SUMS`.
