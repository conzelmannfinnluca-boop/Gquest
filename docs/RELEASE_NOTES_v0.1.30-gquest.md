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
| `Gquest.apk` | 59.526.869 Bytes | `918ec8d0678e863d8358fdcc0a07dbf77726de84501dcfebb153099ef6adf795` |
| `verification.json` | 2,4 KB | `7f3e97fbbb8129f773385bde547e3faa505182092b24864cbfdfefacc6488b5a` |
| `SHA256SUMS` | Prüfsummenliste | — |

Prüfen:

```sh
sha256sum -c SHA256SUMS
apksigner verify --print-certs Gquest.apk
```

## Was in diesem Build neu ist

**Bestätigt (Harness, ohne Headset):**

- **Hand-Pipeline** (`gquest_wrist_hud.lua`): ein Ergebnis pro Frame, damit eine Hand nicht
doppelt geglättet wird; eine NaN- oder ungültige Probe hält die letzte Pose, statt die Hand
verschwinden zu lassen; `vel`/`angvel` kommen aus der veröffentlichten Pose; `ResetHand` setzt
auch den Glättungsfilter zurück, sodass ein Recenter schnappt statt zu gleiten.
- **H3VR-artige Waffenmechanik** (`gquest_weapon_mechanics.lua`, `gquest_mech_gestures.lua`):
Patrone im Lager getrennt vom Magazin, Magazin behält seinen Reststand, Einsetzen lädt nicht
durch, Durchladen befördert die geladene Patrone in die eigene Reserve, leere Kammer klickt,
Verschluss sperrt, Sicherung blockiert, Trommel/Pumpe/Bolzen mit eigenem Verhalten.
Invariante: Kammer + Magazin ist immer genau der Clip-Wert der Engine.
- Zwei neue Lua-Harnesses (`test_hand_pipeline.lua`, `test_weapon_mechanics.lua`); die
Prüfbasis wächst auf 14 Lua-Harnesses und 44 Prüfungen, `--units` bleibt bei 8/8 Gruppen grün.

**Unbestätigt (NOT TESTED, braucht das Headset):**

- Ob `EntityFireBullets` bei den nativen HLVR-Waffen überhaupt aufgerufen wird. Wenn nicht,
verhalten sich die Waffen unverändert — die Mechanik blockiert dann nichts.
- Ob die Support-Hand-Geste „nach hinten ziehen" in der Praxis auslöst; die Standardwerte
(`gquest_mech_reach 6`, `gquest_mech_travel 4`) sind geschätzt, nicht eingemessen.
- Ob sich das Durchladen richtig anfühlt.

Details, Bedienung und Grenzen: `docs/H3VR-WAFFENMECHANIK.md`.

Zu H3VR: übernommen wird nur das Bedienkonzept, keine Datei, kein Modell, kein Klang. H3VR ist
ein kommerzielles Spiel von RUST LTD; die genannten Videos und das Workshop-Addon waren nur
Zielbeschreibung und sind weder ausgelesen noch enthalten.

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

## Installation auf einem frischen Gerät

**Es kollidiert nicht mit der offiziellen GDroid-App.** Die Basis heißt `com.gmodvr.flat`, dieses
Paket `com.gmodvr.qvrx` — bewusst umbenannt, damit es daneben installiert werden kann.

**Ein Update über einen älteren Gquest-Build** ist ein normales Upgrade: dieses Paket hat
versionCode 75, der Vorgänger 74, gleicher Schlüssel `CN=Android Debug`. Es genügt

```sh
adb install Gquest.apk
```

ohne `-r`, und in der App-Info steht als Version `0.1.30-gquest.2` — daran ist der Build auf dem
Gerät erkennbar. (SideQuest schickt ohnehin `-r`.)

**Nur wenn der alte Build mit einem anderen Schlüssel signiert wurde**, bricht es mit
`INSTALL_FAILED_UPDATE_INCOMPATIBLE` ab. In dem Fall zuerst die alte Installation entfernen
**und die App-Daten behalten**:

```sh
adb uninstall -k com.gmodvr.qvrx
adb install Gquest.apk
```

`-k` ist wichtig: ohne es verschwindet auch `files/user/vr_content/`. SideQuest zeigt bei diesem
Fall nur „Install failed (unknown)" — der echte Code steht in der `adb install`-Ausgabe.

| | offizielle GDroid 0.1.30 | dieses APK |
|---|---|---|
| Paket | `com.gmodvr.flat` | `com.gmodvr.qvrx` |
| versionCode / versionName | 74 / 0.1.30 | **75 / 0.1.30-gquest.2** |
| minSdk / targetSdk | 26 / 35 | 26 / 35 |
| ABI | `arm64-v8a` | `arm64-v8a` |
| native Bibliotheken | 34 | 35 (plus `liblauncheq.so`) |
| Signatur | `CN=Source Android Local Build`, v2+v3 | `CN=Android Debug`, v2+v3 |

Daraus folgt für die Installation:

- **Frische Installation:** `adb install Gquest.apk` — oder Datei im Dateimanager
  öffnen. Beide Apps können gleichzeitig installiert sein.
- **`-r` über die offizielle GDroid-App ist nicht nötig und nicht möglich**, weil es ein anderes
  Paket ist.
- **Die Signatur zählt beim Aktualisieren von GQuest selbst.** Ein späterer GQuest-Build mit
  anderem Schlüssel lässt sich nicht über diesen legen (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`);
  dann vorher deinstallieren. Wer selbst baut, behält seinen eigenen Schlüssel und kann ohne
  Deinstallation aktualisieren.

Voraussetzungen: Quest 3/3S oder ein anderes arm64-Gerät, Android 8+ (minSdk 26).

**Es ist kein Content-Paket.** Enthalten sind 16 Lua-Dateien des Overlays. Karten und
Waffenmodelle fehlen; der Installer schreibt beim Start nur diese Lua-Dateien und lässt
vorhandenen Content unangetastet.

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
- **16-KB-Seiten:** alle nativen Bibliotheken haben `p_align` 16384, auch die eigene
  `liblauncheq.so` (der Linker bekommt `-Wl,-z,max-page-size=16384`). Mit `targetSdk 35` wäre
  eine 4-KB-Ausrichtung auf Android-15-Geräten mit 16-KB-Seiten ein Ladefehler.
  `extractNativeLibs` steht auf `true`, die Ausrichtung im ZIP spielt deshalb keine Rolle.

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

## Log des ersten Starts

Der Hardwaretest lässt sich protokollieren, statt ihn zu erinnern:

```sh
adb logcat -d > quest-start.log
python3 Gquest-Hybrid/tools/evaluate_hardware_log.py quest-start.log
```

Beurteilt werden sieben Bereiche: Launcher-Start (`GQUEST_RUST READY`/`STOP`), Content-Installation
(`CONTENT ready=… installed=… existing=…`), Geräteerkennung (`DEVICE detected=…`), die
Glättungsstufe, die den Filter wirklich erreicht hat (`GQUEST_HANDSMOOTH level=… tau=…`), die
Hand-Pipeline (`GQUEST_HANDS hand=… state=ok|held drops=…`), die Waffenmechanik
(`GQUEST_MECH action=… chamber=… mag=… total=…`) und die Gesten (`GQUEST_MECHGESTURE mag|rack`).
Fehlt eine Zeile, steht dort **UNBEKANNT** — nicht „in Ordnung".

Die Mechanik wird nicht nur gezählt, sondern geprüft: `Kammer + Magazin` muss die Summe ergeben,
ein Schuss muss die Summe um genau eins senken, und sie darf nur bei Magazinwechsel oder
Nachladen wieder steigen. Ein `GQUEST_MECH write refused` ist ein Fehler, keine Warnung: dann
folgt die Waffe der Engine und nicht dem Modell. Eine fehlende VR-Aktion
(`GQUEST_MECHGESTURE action_inactive=…`) ist eine Warnung — die Taste löst dann nichts aus, die
Konsolenbefehle `gquest_mech_*` bleiben der Weg.

## Automatisch geprüft — ohne Headset

```
python3 Gquest-Hybrid/tools/build.py --tests     # 41 Prüfungen, 11 Gruppen, Exit 0
```

12 C++-Grenztests, 9 Rust-Unit-Tests, C++/Rust-ABI-Smoke, Bridge-Cross-Compile für
`aarch64-linux-android29` mit `-Werror`, 7 Werkzeug-Selbsttests, 12 Lua-Harnesses.
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
python3 Gquest-Hybrid/tools/build.py --tests            # 42 Prüfungen, ohne private Daten
python3 Gquest-Hybrid/tools/build.py                    # volles APK
```

Die Reihenfolge und die nötigen Umgebungsvariablen für den Rust-Cross-Build stehen in
`BUILD.md`. Ergebnis: `Gquest-Hybrid/dist/Gquest.apk` plus `verification.json`.
Mit eigenem Schlüssel signiert installiert das auch über eine bestehende eigene Installation.

Lizenz des eigenen Codes: MIT (`LICENSE`). Fremdanteile: `THIRD_PARTY_NOTICES.md`.
