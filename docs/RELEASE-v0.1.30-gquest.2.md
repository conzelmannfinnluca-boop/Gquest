# Gquest 0.1.30-gquest.2 (versionCode 75)

VR-Overlay auf GDroid 0.1.30 für Quest 3 / Quest 3S. Dieses Paket enthält **den Content**
(218 Modelle, 128 Materialien, 12 Waffenscripts) und **18 Lua-Dateien** des Overlays.

| Datei | Größe | SHA256 |
|---|---|---|
| `Gquest-0.1.30-gquest.2-slim.apk` (ohne die 14 großen 4K-Waffentexturen) | 139.464.174 Bytes | `70abe8fd14918cd73bbb7985588b9604c2dd8c68a8cc6c031d299ee2846a4c37` |
| `Gquest.apk` (vollständig) | 283.456.755 Bytes | `5148f8bfeead6249bc2a235a64d5ba228539e4d63ca0f12cb14b1b43267619f5` |

Die vollständige Datei gibt es zusätzlich zweigeteilt (`…apk00.part` 209.715.200 Bytes +
`…apk01.part` 73.741.555 Bytes) für Kanäle mit 256-MB-Grenze: herunterladen, mit
`cat teil1 teil2 > Gquest.apk` (Windows: `copy /b`) zusammenfügen, Prüfsumme vergleichen.

## Installieren

```sh
adb install -r Gquest.apk
```

Bei `INSTALL_FAILED_UPDATE_INCOMPATIBLE` (anderer Signaturschlüssel): `adb uninstall -k com.gmodvr.qvrx`,
dann installieren. Platz am Headset: gut 300 MB.

## Was drin ist

- **Waffenpanel** (VR-Menü → Waffen): elf HL2-Waffen, sechs Mechanik-Knöpfe, Live-Zeile
  `Waffe: … - Kammer 1, Magazin 17/18, Sicherung aus, Verschluss zu`. Ohne Zahlen nennt die
  Zeile den Grund (nichts in der Hand, Waffe ohne Mechanik, Engine-Wert unlesbar).
- **Manuelle Mechanik:** getrennte Kammer, Magazin behält Restmunition, Durchladen in die
  Reserve, Verschluss sperrt, Sicherung blockiert, Trommel/Pumpe/Bolzen.
- **Waffenwechsel** wird im selben Tick gepusht; die bestätigte Zeile bleibt einstellbar lang
  stehen (VR-Einstellungen → `Waffen-Lesezeit`).
- **Hand-Pipeline:** eine Pose pro Frame, Haltepose bei unbrauchbarer Probe statt Zucken,
  Diagnose über `gquest_hands_state`.

## Grenzen

- Nur arm64, Android 8+ (minSdk 26). Keine Karten im Paket.
- Der Lauf auf dem Headset ist **nicht** getestet: weder Handdarstellung noch Waffenmodelle im
  Spiel wurden auf einem Gerät bestätigt. Was geprüft ist, steht im Repository
  (`docs/`, 11 Lua-Harnesses, Signatur- und ZIP-Prüfung).
- Basis ist das offizielle GDroid 0.1.30; geändert sind nur das Manifest, ein auditierter
  Client-Befehl, die eigene Launcher-Bibliothek und die Overlay-Dateien.

## Content-Herkunft

Modelle, Materialien und Waffenscripts stammen aus dem eigenen Release `test-von-Gqeust` dieses
Projekts und sind byteweise übernommen (358 von 358 Dateien geprüft). Nicht zur
Weiterverbreitung bestimmt; Rechte an den Assets liegen beim jeweiligen Rechteinhaber.
