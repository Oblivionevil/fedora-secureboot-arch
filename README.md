# Fedora-Kernel + Fedora shim/GRUB für Arch Linux (Secure Boot für EAC Linux v2)

Mit diesem Setup startet Arch Linux über die **unveränderten, von Fedora bzw. Microsoft signierten**
Binärdateien – also so, wie EAC Linux v2 es verlangt:

```
UEFI (Werks-Schlüssel) → shimx64.efi (Microsoft UEFI CA) → grubx64.efi (Fedora) → vmlinuz (Fedora) → Arch-Userspace
```

| Paket | Inhalt |
|---|---|
| `linux-fedora` | Fedora-Kernel + alle Module (`kernel-core`, `-modules-core`, `-modules`, `-modules-extra`), byte-identisch |
| `fedora-shim-grub` | Fedora `shimx64.efi`, `mmx64.efi`, `grubx64.efi` + `fedora-sb-sync`, `fedora-sb-check`, pacman-Hooks |

Alle RPMs werden beim Bauen gegen die hier hinterlegten Fedora-Schlüssel geprüft
(`keys/`, Fingerprints abgeglichen mit <https://fedoraproject.org/security/>):

| Release | Fingerprint |
|---|---|
| Fedora 44 | `36F6 12DC F27F 7D1A 48A8 35E4 DBFC F71C 6D9F 90A6` |
| Fedora 45 | `4F50 A611 4CD5 C697 6A7F 1179 655A 4B02 F577 861E` |

## Updates

* Eine GitHub Action prüft alle 3 Stunden die **stabilen** Fedora-Repos (`updates` + `releases`) und
  schreibt die exakte Version in `kernel.env` bzw. `bootloader.env` auf die Branches
  `versions-kernel` und `versions-bootloader`.
* Ein Buildserver beobachtet diese Branches und baut die Pakete neu, sobald sich eine Version ändert.
  Die Rezepte selbst bleiben dabei unverändert.
* Ein neues Fedora-Release wird erst verwendet, wenn sein Schlüssel in `keys/` und in den
  Paketordnern liegt.

Alternativ lokal bauen – `fedora-shim-grub` zuerst, damit beim Entfernen des Arch-Kernels schon
der Fedora-Bootloader bereitsteht:

```bash
cd fedora-shim-grub && makepkg -si    # braucht rpm-tools
cd ../linux-fedora && makepkg -si
```

`FEDORA_SB_REPO` und `FEDORA_MIRROR` überschreiben Versions-Repo und Mirror.

## Einrichtung

```bash
sudo fedora-sb-check                  # zeigt, was für EAC noch fehlt
sudo fedora-sb-sync --bootorder-first # Fedora-shim als ersten UEFI-Eintrag setzen
```

Im UEFI-Setup:

1. Secure-Boot-Schlüssel auf **Werkseinstellung** zurücksetzen, falls eigene Schlüssel (z.B. von
   sbctl) eingeschrieben sind – EAC akzeptiert nur bekannte Schlüssel. Die db muss das Microsoft
   UEFI CA 2011 oder 2023 enthalten.
2. Secure Boot einschalten, VT-d/AMD-Vi (IOMMU) eingeschaltet lassen.
3. Neu starten → „Arch Linux - Fedora-Kernel (Secure Boot / EAC)“.
4. `sudo fedora-sb-check` – alle Punkte sollten erfüllt sein.

**Keine MOK-Schlüssel einschreiben** (`mokutil --import`): EAC wertet selbst eingeschriebene
Schlüssel als unbekannt.

## Nur Fedora-GRUB und Fedora-Kernel

Für EAC Linux v2 bleiben nur der Fedora-GRUB und der Fedora-Kernel installiert:

* `linux-fedora` ersetzt die Arch-Kernel (`linux`, `linux-lts`, `linux-zen`, `linux-hardened`,
  `linux-rt`, `linux-rt-lts`), `fedora-shim-grub` ersetzt `grub`, `refind` und `limine`. pacman fragt
  beim Installieren, ob sie entfernt werden sollen. Pakete, die vom Arch-Kernel abhängen (z.B. `nvidia`),
  müssen mit entfernt werden.
* Das GRUB-Menü enthält nur den Fedora-Kernel (dazu Windows, die UEFI-Einstellungen und eigene
  Einträge).
* Steht in der UEFI-Startreihenfolge noch ein anderer Linux-Bootloader (z.B. Arch-GRUB) vorne, setzt
  `fedora-sb-sync` den Fedora-shim davor, sobald nur noch `linux-fedora` installiert ist. Sonst würde
  der alte Bootloader einen gelöschten Kernel suchen.
* Was pacman nicht entfernt, also alte Bootloader auf der ESP (z.B. `EFI/GRUB`), deren UEFI-Einträge
  und AUR-Kernel, zeigt `sudo fedora-sb-check` jeweils mit dem Befehl zum Entfernen.

## Einstellungen aus dem ursprünglichen GRUB

`fedora-sb-sync` baut `ESP/EFI/fedora/grub.cfg` wie `grub-mkconfig` aus `/etc/default/grub` und
`/etc/grub.d/40_custom`. Die Einstellungen bleiben also, wo sie waren. Nach einer Änderung
`sudo fedora-sb-sync` statt `grub-mkconfig` ausführen. Entfernt pacman Arch-`grub`, landen geänderte
Dateien als `.pacsave`; `fedora-sb-sync` legt sie wieder an ihren Platz.

Übernommen werden:

| Bereich | Einstellungen |
|---|---|
| Standardeintrag | `GRUB_DEFAULT` (auch `saved`), `GRUB_SAVEDEFAULT`, `grub-reboot`-Einträge (`next_entry`); `grubenv` liegt unter `ESP/EFI/fedora/` |
| Menü | `GRUB_TIMEOUT`, `GRUB_TIMEOUT_STYLE`, `GRUB_DISTRIBUTOR`, `GRUB_DISABLE_RECOVERY`, `GRUB_DISABLE_SUBMENU`, `GRUB_DISABLE_OS_PROBER` (Windows auf der ESP) |
| Kernel | `GRUB_CMDLINE_LINUX`, `GRUB_CMDLINE_LINUX_DEFAULT`, `GRUB_CMDLINE_LINUX_RECOVERY`, `GRUB_DISABLE_LINUX_UUID`, `GRUB_DISABLE_LINUX_PARTUUID`, `GRUB_EARLY_INITRD_LINUX_STOCK`/`_CUSTOM` |
| Anzeige | `GRUB_TERMINAL`, `GRUB_TERMINAL_INPUT`/`_OUTPUT`, `GRUB_SERIAL_COMMAND`, `GRUB_GFXMODE`, `GRUB_GFXPAYLOAD_LINUX`, `GRUB_VIDEO_BACKEND`, `GRUB_FONT`, `GRUB_THEME`, `GRUB_COLOR_NORMAL`/`_HIGHLIGHT`, `GRUB_INIT_TUNE`, Sprache aus `LANG` (Übersetzungen aus `/boot/grub/locale`) |
| Sonstiges | `GRUB_PRELOAD_MODULES`, `GRUB_ENABLE_CRYPTODISK` (verschlüsseltes `/boot`), eigene Einträge aus `40_custom` und `custom.cfg` |

Nicht übernommen werden `GRUB_BACKGROUND` (dem Fedora-GRUB fehlt `background_image`; ein Theme geht)
sowie die Einträge aus `31_efi_bootnext` (Modul fehlt) und andere Skripte in `/etc/grub.d`.
Unter Secure Boot lädt der Fedora-GRUB nur seine eingebauten Module.
`/etc/fedora-sb.conf` kann den Timeout, die Kommandozeile und den Windows-Eintrag überschreiben.

## Was sich unter dem Fedora-Kernel ändert

* Kernel-Parameter: die aus `/etc/default/grub` plus
  `lockdown=integrity sysctl.kernel.kexec_load_disabled=1 iommu.passthrough=0` (Intel: `intel_iommu=on`).
  Die EAC-Parameter lassen sich in `/etc/fedora-sb.conf` anpassen, danach `sudo fedora-sb-sync`.
* Es laden nur Fedora-signierte Module; DKMS-/Out-of-tree-Module funktionieren nicht. Für den
  Fedora-Kernel werden bewusst keine Header installiert, damit DKMS dort nichts baut.
* Hibernate ist durch Lockdown gesperrt, Suspend funktioniert.
* mkinitcpio-Post-Hooks (z.B. sbctl) sind für `linux-fedora` abgeschaltet (`--nopost` im Preset),
  damit der Fedora-Kernel nicht neu signiert wird.

## Grenzen

Epic hat EAC Linux v2 im Oktober 2026 angekündigt. Offiziell unterstützt sind nur einige
Distributionen (u.a. Ubuntu, Fedora, Debian). Ein Arch-Userspace mit Fedora-Kernel erfüllt die
veröffentlichten Boot-Anforderungen; ob zusätzlich der Userspace geprüft wird, ist nicht dokumentiert.
