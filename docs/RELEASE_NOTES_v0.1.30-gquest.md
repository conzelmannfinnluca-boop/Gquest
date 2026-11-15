# GQuest 0.1.30-gquest — Release-Notes

## Was dieses Release ist

Ein Overlay auf die offizielle **GDroid 0.1.30** (`com.gmodvr.qvrx`, arm64-v8a, Quest 3/3S).
Es ersetzt keine Engine und bringt kein Spiel mit: eigener Launcher-Anteil, eigene Bridge und
eigenes Lua werden in das Basispaket gelegt. Engine, Renderer und Spielinhalte kommen
unverändert von GDroid.

Ausgeliefert werden drei Dateien: das APK, `verification.json` (Digest und Payload-Prüfung) und
`SHA256SUMS`. Der Quellstand dazu ist der Commit, den der Tag nennt.

## Dateien

| Datei | Größe | SHA256 |
|---|---|---|
| `Gquest-Rust-GDroid.apk` | 59.518.440 Bytes | `195f572f259154127ae74c55bd13f7609f60cb4cd471b487cdb6b7c573461791` |
| `verification.json` | 2,2 KB | `74564cca4377fda785af9de211b3bac72db4aa560d54b4f99f018b2b3fe36223` |
| `SHA256SUMS` | Prüfsummenliste | — |

Prüfen:

```sh
sha256sum -c SHA256SUMS
apksigner verify --print-certs Gquest-Rust-GDroid.apk
```

## Herkunft und Rechte — bitte zuerst lesen

**Dieses APK enthält fremde Bestandteile.** Es ist kein eigenständiges Produkt und nicht von
den GDroid-Entwicklern veröffentlicht oder unterstützt.

| Bestandteil | Herkunft | Rechte |
|---|---|---|
| Engine (`libclient.so` u. a., **gepatcht**) | GDroid 0.1.30, Basis auf nillerusr's Android Source | GDroid-Repository enthält **keine Lizenzdatei**; eine Weiterverbreitungserlaubnis ist daraus nicht ableitbar |
| App-Gerüst (`classes.dex`, `AndroidManifest.xml`) | GDroid 0.1.30 | wie oben; das Manifest ist auf `com.gmodvr.qvrx` umgeschrieben |
| Touch-Steuerung | laut GDroid-Credits von IzuIzu | wie oben |
| Spielinhalte (Garry's Mod, Source) | Valve / Facepunch | **nicht enthalten**, müssen aus einer eigenen Steam-Kopie stammen |
| Eigener Code (Bridge, Rust-Runtime, Lua) | dieses Repository | MIT, siehe `LICENSE` |

Das APK enthält **keine Retail-Spieldateien**. Es setzt eine eigene Steam-Kopie von Garry's Mod
voraus, so wie GDroid selbst (rund 7 GB mit Addons).

Wer diese Datei weiterverbreitet, tut das auf eigene Verantwortung. Wenn der GDroid-Autor oder
Rechteinhaber der enthaltenen Bestandteile widerspricht, gehört das Release entfernt — die
Quellen bleiben nutzbar, siehe „Selbst bauen".

## Installation

**Die Signatur unterscheidet sich von der offiziellen GDroid-App.** Nachgeprüft mit
`apksigner`:

| Paket | Signierer | Zertifikat SHA256 |
|---|---|---|
| offizielle GDroid 0.1.30 | `CN=Source Android Local Build` | `4ea5579e427cd59f…` |
| dieses APK | `CN=Android Debug` | `7013b3046d18208f…` |

Android verlangt bei einem Update denselben Signierer. Daraus folgt:

- **`adb install -r` über eine offizielle GDroid-Installation schlägt fehl**
  (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).
- Wer es installieren will, muss die offizielle App vorher **deinstallieren** — dabei gehen
  App-Daten und Einstellungen verloren. GDroid bietet vorher *Settings & tools → Back up
  saves*.
- Wer ohnehin selbst baut (eigener Debug-Schlüssel), kann diesen Build über seine eigene
  Installation legen, sofern der Schlüssel derselbe ist.

```sh
adb install Gquest-Rust-GDroid.apk
```

Voraussetzungen: Quest 3/3S, arm64-v8a, Android 8+ (minSdk 26), `versionCode` 74.

**Es ist kein Content-Paket.** Enthalten sind 16 Lua-Dateien des Overlays. Karten und
Waffenmodelle fehlen; der Installer schreibt beim Start nur diese Lua-Dateien und lässt
vorhandenen Content unangetastet. Auf einer Installation ohne Content fehlt also der Inhalt,
nicht die Funktion.

## Was im Paket steckt

Gegenüber der Basis-APK geprüft, Eintrag für Eintrag:

- **geändert:** `AndroidManifest.xml`, `classes.dex`, `lib/arm64-v8a/libclient.so` — nur diese
  drei, wie die Payload-Regel es fordert
- **neu:** 18 Einträge — `lib/arm64-v8a/liblauncheq.so`, 16 Lua-Dateien unter
  `assets/quest_lab_vr_content/` und `assets/quest_lab_vr_content.tsv`; dazu die drei neuen
  Signaturdateien `META-INF/ANDROIDD.RSA`, `ANDROIDD.SF` und `MANIFEST.MF` (21 Einträge gesamt)
- **entfernt:** 14 `META-INF/`-Einträge der ursprünglichen Gradle-Werkzeuge (androidx- und
  Kotlin-Metadaten); sie werden beim Neusignieren ersetzt, kein Inhalt geht verloren
- **unverändert:** 33 der 34 nativen Bibliotheken, Byte für Byte; die 34. ist `libclient.so`
  mit dem gepatchten VR-Init

## Trägerbestätigt auf Quest 3

Von dir im Headset bestätigt, Belege in `docs/Gquest-HL2-*-verification.json`:

- Nachladen und Schießen für **alle sieben** nativen HL2-Feuerwaffen (Pistole, SMG, Shotgun,
  AR2, .357, Crossbow, RPG)
- Treffer und Schaden für Shotgun, AR2, .357, Crossbow, RPG
- Pistolen-Ausrichtung; SMG zweihändig stabil und einhändig korrekt nach Griff-Cache-Korrektur
- Brechstangen-Richtung je Waffenklasse
- ArcVR vollständig entfernt, 63 Dateien beim ersten Start gesichert

Die vollständige native Kette aus Magazin, Reserve, Kammer und Zustand ist als Log **nur für die
Pistole** hinterlegt. Die anderen sechs sind Trägerberichte ohne Mitschnitt.

## Automatisch geprüft — ohne Headset

```
python3 Gquest-Hybrid/tools/build.py --tests     # 41 Prüfungen, 11 Gruppen, Exit 0
```

12 C++-Grenztests, 9 Rust-Unit-Tests, C++/Rust-ABI-Smoke, Bridge-Cross-Compile für
`aarch64-linux-android29` mit `-Werror`, 6 Werkzeug-Selbsttests, 12 Lua-Harnesses.
`verification.json` hält zusätzlich Signaturprüfung, ZIP-CRC und Payload-Identität fest.

## Ausdrücklich nicht bestätigt

| Offen | Stand |
|---|---|
| Lauf auf einem Headset | **nicht getestet**; `verification.json` sagt `quest_test: pending` |
| Quest 3S | kein Hardwaretest, alle Aussagen sind von einer Quest 3 |
| Handglättung (Aus/Mild/Stark) | Wirkung nicht gespürt; 30/60 ms sind Vorgaben |
| Menü-Layout | nicht im Headset gesehen; 898 px sind gerechnet |
| Frametimes auf dem Gerät | Instrumentierung fertig, keine Messung |
| Sitzend/Stehend | gespeichert, wirkt erst mit dem Core-Umstieg (E1) |
| Content im Paket | **nicht enthalten** (siehe oben) |
| 1:1-Parität zu PCVR/Addons | nicht erreicht, nicht behauptet |

## Selbst bauen

```sh
python3 Gquest-Hybrid/tools/build.py --check            # was fehlt, mit Beschaffungsweg
python3 Gquest-Hybrid/tools/verify_base_apk.py         # gelieferte Basis-APK gegen alle Pins
python3 Gquest-Hybrid/tools/build.py --tests            # 41 Prüfungen, ohne private Daten
python3 Gquest-Hybrid/tools/build.py                    # volles APK
```

Die Reihenfolge und die nötigen Umgebungsvariablen für den Rust-Cross-Build stehen in
`BUILD.md`. Ergebnis: `Gquest-Hybrid/dist/Gquest-Rust-GDroid.apk` plus `verification.json`.
Mit eigenem Schlüssel signiert installiert das auch über eine bestehende eigene Installation.

Lizenz des eigenen Codes: MIT (`LICENSE`). Fremdanteile: `THIRD_PARTY_NOTICES.md`.
