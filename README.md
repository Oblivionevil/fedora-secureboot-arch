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

Alternativ lokal bauen:

```bash
cd linux-fedora && makepkg -si        # braucht rpm-tools
cd ../fedora-shim-grub && makepkg -si
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

## Was sich unter dem Fedora-Kernel ändert

* Kernel-Parameter: die aus `/etc/default/grub` plus
  `lockdown=integrity sysctl.kernel.kexec_load_disabled=1 iommu.passthrough=0` (Intel: `intel_iommu=on`).
  Anpassen in `/etc/fedora-sb.conf`, danach `sudo fedora-sb-sync`.
* Es laden nur Fedora-signierte Module; DKMS-/Out-of-tree-Module funktionieren nicht. Für den
  Fedora-Kernel werden bewusst keine Header installiert, damit DKMS dort nichts baut.
* Hibernate ist durch Lockdown gesperrt, Suspend funktioniert.
* Andere Kernel (z.B. Arch-`linux`) stehen im Menü, starten aber nur ohne Secure Boot.
* mkinitcpio-Post-Hooks (z.B. sbctl) sind für `linux-fedora` abgeschaltet (`--nopost` im Preset),
  damit der Fedora-Kernel nicht neu signiert wird.

## Grenzen

Epic hat EAC Linux v2 im Oktober 2026 angekündigt. Offiziell unterstützt sind nur einige
Distributionen (u.a. Ubuntu, Fedora, Debian). Ein Arch-Userspace mit Fedora-Kernel erfüllt die
veröffentlichten Boot-Anforderungen; ob zusätzlich der Userspace geprüft wird, ist nicht dokumentiert.
