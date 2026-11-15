# Gquest 0.1.30-gquest.2 (versionCode 75)

VR-Overlay auf GDroid 0.1.30 für Quest 3 / Quest 3S. Dieses Paket enthält **den Content**
(218 Modelle, 128 Materialien, 12 Waffenscripts) und **18 Lua-Dateien** des Overlays.

| Datei | Größe | SHA256 |
|---|---|---|
| `Gquest.apk` | 283.456.755 Bytes | `c43b44a2d9ef54cdbb9a4354e9449e07ca4976d3cc3fd2ba010bb6223b90cc60` |

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
