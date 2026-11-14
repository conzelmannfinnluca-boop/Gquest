# GQuest — PROJECT STATUS

Stand: 14. November 2026
Aktuelle Phase: **1 abgeschlossen, 2 als Entwurf abgeschlossen, 3 blockiert**
Letzter Commit vor diesem Stand: `6318a5d` (HL2 manual reload/shooting für sieben
Waffenfamilien protokolliert)

Dieses Dokument ist die Wahrheit über den Projektstand. Wenn hier
„PARTIALLY IMPLEMENTED“ steht, ist die Funktion **nicht** fertig, auch wenn Code
existiert.

---

## 1. Was GQuest heute tatsächlich ist

Ein **experimentelles VR-Overlay** auf der geschlossenen GDroid-0.1.30-APK
(`com.gmodvr.qvrx`), bestehend aus:

- eigenem C++-Bridge (`liblauncheq.so`, 552 Zeilen),
- eigener Rust-Startkomponente (210 Zeilen, 5 Tests),
- eigenem GLua-Modul `gquest_vr` (C++, 170 Zeilen),
- Lua-Overlay (~1.090 Zeilen) für Waffen, Nachladen, Menü und Tracking,
- nativen ARM64-Hooks für Fingerprofile und linke Handfläche,
- nachweislich auf **Quest 3** gelaufen und vom Träger bestätigt.

GQuest ist **kein** eigenständiges Spiel, **keine** eigene Engine und **kein**
PCVR-Produkt. Die Bezeichnung „GQuest V2“ in diesem Repository meint den geplanten
Nachfolger, nicht etwas, das bereits existiert.

---

## 2. Systemstatus

Legende: **DONE** · **IN DEVELOPMENT** · **PARTIALLY IMPLEMENTED** · **BLOCKED** ·
**NOT TESTED** · **FAILED** · **NOT STARTED**

| System | Status | Beleg / Anmerkung |
|---|---|---|
| Rust-Startprofil + Launch-Argumente | DONE | 5 Unit-Tests im Code; Injection-Test vorhanden |
| C++/Rust-ABI | DONE | `ffi_smoke.cpp` (benötigt Rust-Lib) |
| VR-Content-Installation (APK→Gerät) | DONE | TSV-Manifest, Größen, Traversal-Schutz, atomar |
| ArcVR-Retirement (63 Dateien) | DONE | C++-Test hier ausgeführt, PASS |
| VR-Lua-API (`gquest_vr`) | DONE | C++-Test hier ausgeführt, PASS |
| Native Fingerprofile (12) | DONE | C++-Test hier ausgeführt, PASS |
| EGL-Context-Sharing | PARTIALLY IMPLEMENTED | läuft, aber GOT-Patch fragil |
| InputSystem-Snapshot-Bridge | PARTIALLY IMPLEMENTED | läuft, Offset-/Stub-gekoppelt |
| Left-Palm-Patch | PARTIALLY IMPLEMENTED | opt-in, nie separat auf Hardware bestätigt |
| Kopf-/Controller-Tracking | DONE (Quest 3) | Trägerbestätigung |
| Hände + Fingerdarstellung | PARTIALLY IMPLEMENTED | rechte Hand profiliert; linke Hand Originalpfad |
| VR-Menü | DONE (Quest 3) | Trägerbestätigung |
| HL2-Pistole | DONE (Quest 3) | vollständige native Zustandsfolge protokolliert |
| HL2-SMG | PARTIALLY IMPLEMENTED | Zweihand stabil (bestätigt); keine native Übergangssequenz |
| HL2-Schrotflinte | PARTIALLY IMPLEMENTED | Nachladen/Schießen bestätigt; keine native Sequenz |
| HL2 AR2 / Magnum / Armbrust / RPG | PARTIALLY IMPLEMENTED | Trägerbestätigung „alle vier funktionieren“, ohne Protokoll |
| Brechstange (Richtung + Nahkampf) | DONE (Quest 3) | Trägerbestätigung |
| Physgun | PARTIALLY IMPLEMENTED | vorhanden als native HL2-Physgun, nicht separat geprüft |
| Toolgun / eigenes Tool-System | NOT STARTED | – |
| Sandbox-Objektmodell, Undo/Redo | NOT STARTED | – |
| 3D-Spawn-Menü (eigenes) | NOT STARTED | Engine-Menü wird genutzt |
| NPC-/KI-System (eigenes) | NOT STARTED | Engine-NPCs verfügbar |
| Fahrzeugsystem (eigenes) | NOT STARTED | – |
| Save-System (eigenes) | NOT STARTED | Engine-Saves |
| Eigener Netcode | NOT STARTED | Engine-Netzwerk |
| Multiplayer über eigene Autorität | NOT STARTED | – |
| Crossplay Quest↔PCVR | **BLOCKED** | GDroid hat keinen PC-Build |
| PCVR-Host | NOT STARTED | – |
| Lua-Sandbox + Permissions | NOT STARTED | Engine-Lua ist nicht sandboxed |
| Mod-Manager / Workshop | NOT STARTED | GDroid-Mod-Manager wird genutzt |
| Map-System / Map-Editor | NOT STARTED | – |
| Performance-HUD | NOT STARTED | – |
| Automatisierte Gerätetests | NOT STARTED | nur manuelle Trägerbestätigung |
| Performance-Sampler + CSV | DONE | `gquest_perf_hud.lua`, 9. Lua-Harness deckt Statistik und Ausgabe ab |
| Performance-Messung auf Quest 3 | NOT TESTED | Instrumentierung fertig, Hardware-Lauf steht aus |
| Geräteprofile Quest 3 / 3S | DONE | eigene Stufensätze, vom Runtime akzeptiert, im Menü wählbar |
| Geräteprofile auf Quest 3S | NOT TESTED | Stufen definiert, aber kein Lauf auf 3S-Hardware |
| Lizenz + Herkunftsnachweis | DONE | `LICENSE` (MIT), `THIRD_PARTY_NOTICES.md`, zlib-Volltext in `third_party/` |

---

## 3. Buildstatus

| Build | Status | Grund |
|---|---|---|
| `build.py --check` | **DONE** | meldet 9 Voraussetzungen + Spiegel-Drift, ohne Traceback |
| `build.py --tests` | **DONE** | 3 C++-Grenztests + 6 Rust-Tests + 10 Lua-Harnesses |
| `Gquest-Hybrid/tools/build.py` (Gesamt-APK) | **BLOCKED** | private Abhängigkeiten fehlen (bewusst) |
| Rust `cargo test` | **DONE** (6 von 6) | Toolchain lokal in `work/toolchains` installiert |
| C++-Grenztests | **DONE** (3 von 3) | siehe Abschnitt 4 |
| Lua-Harnesses (10) | **DONE** (10 von 10) | lokale Lua-5.4-Toolchain gebaut |
| C++/Rust-ABI-Smoke | **DONE** | `cargo build --release` + `ffi_smoke.cpp`, 6 Startfälle
| APK-Verifikation | **BLOCKED** | kein Basis-APK |

Fehlende, bewusst nicht versionierte Voraussetzungen: `outputs/GDroid-0.1.30.apk`,
`work/gdroid-0.1.30-native/`, `work/android-sdk/`, `work/toolchains/`,
`work/quest-vr-content/`, `work/quest-vr-content-manifest.json`, Debug-Keystore,
Spielinhalte. Der frühere `rtk proxy`-Wrapper ist entfernt; `build.py --check` listet
diese Dateien jetzt einzeln mit Zweck und Beschaffungsweg auf.

---

## 4. Teststatus (in dieser Sitzung tatsächlich ausgeführt)

Umgebung: Linux, `g++ 13.3.0`, `python3 3.12.3`, keine private APK. Lua 5.4.7 und eine
Rust-stable-Toolchain wurden lokal nach `work/toolchains/` installiert (per `.gitignore`
ausgeschlossen, Reinstallationsanleitung in BUILD.md).

Ein Befehl, reproduzierbar:

```sh
python3 Gquest-Hybrid/tools/build.py --tests
```

Ergebnis: **3 C++-Grenztests, 6 Rust-Tests, C++/Rust-ABI-Smoke und 10 Lua-Harnesses
bestanden**, Exit-Code 0.

Rust-Tests:
- Startargumente: Profil-Einstellungen und `+hlvr_isvrplayer` stehen vor `+map`, `-vr` an Index 1
- Alle sechs Gerätestufen parsen; Geräte- und Preset-Zeilen werden vom Runtime ignoriert
- Ungültige Profilwerte können keine Engine-Kommandos einschleusen (Injection-Test)
- CRLF und alle Auflösungsstufen bleiben erhalten
- Explizite Level-Kommandos (`+connect`, `+load`, `+changelevel`) werden nicht überschrieben
- FFI behandelt Nullzeiger, hält `argv` eigentümerrichtig und nullterminiert

C++-Grenztests:
- `PASS native finger wrapper: all profiles, left/root/flags untouched, original input interpolation, invalid/off passthrough`
- `PASS explicit native action sets: weapon/eject, both hands, missing set/action, inactive, invalid hand and embedded-NUL guards`
- `PASS VR Lua bridge: both hands/head/aim, quaternion axes, real validity/finite gates, input routing, inactive/invalid input and bounded haptics`
- `PASS ArcVR retirement: 63 owned files backed up, unrelated addon retained, repeated launch, backup collision and symlink guard`

Lua-Harnesses (10/10):
- Griff-Cache: echte modelllokale Anker, Null-Baseline-Regression, vier Teil-Schreib-Rollbacks, finite/range/schema-Guards
- Mündung und Einhand-Frames: umgekehrte Retail-Achsen ersetzt, Munition erhalten, sieben Rollback-Grenzen, Crowbar ohne Vordergriff
- Brechstangen-Richtung: exakter bestätigter Pitch, wiederholtes Deploy idempotent, Schusswaffen isoliert
- Native Modellpolitik: elf Klassen, Zuweisung nach Deploy, Desktop/Mod/NPC/MP/Tod/fehlendes Modell ausgeschlossen
- HL2-Ausrüstung: elf Klassen, persistente Munition, Allowlist, SP-/Alive-Guards
- Waffenkatalog: elf echte Auswahlen, keine ArcVR-Bedienung
- Pose-Gate und Reload-Client: HLVR-Aliase, linke Hand/Session/Tod-Gates, kein doppeltes Eject
- Performance-Sampler: konstante Bildrate, Hitch-Erkennung, 1%-Low, Fenster-Klemmen und -Überlauf, Ablehnung von nan/inf/Null, Disable-Gate, CSV-Form und Header-einmalig, Summary- und Overlay-Gates
- Geräteprofile: getrennte Stufensätze beider Geräte (alle sechs vom Runtime akzeptiert), Defaults deckungsgleich mit dem Runtime-Default, Altformat- und CRLF-Parsing, Fremdstufen-Snap, Rückfall bei ungültigen Werten, gemerkte Presets über Gerätewechsel, Setter-Guards, stabiler Round-Trip
- Menü-Navigation: Root → Ausrichtung → Zurück → Schließen → Wiederöffnen → Waffen

Zusätzlich geprüft: `--check` meldet alle 9 fehlenden Voraussetzungen mit Zweck und
Beschaffungsweg; ohne `liblua5.4` meldet der Test-Modus `SKIPPED` statt `FAIL`.

**Nicht ausgeführt:** APK-Verifikation, Android-Cross-Build, jeder Hardware-Test, jede
Frametime-Messung auf einem Headset. Diese Liste ist absichtlich vollständig — nichts
davon wird als bestanden behauptet.

---

## 5. Quest-3-Status

**PARTIALLY IMPLEMENTED, hardwarebestätigt.**

Bestätigt vom Träger auf Quest 3:
Kopf-/Controller-Tracking, Hände, VR-Menü, Pistole (Ausrichtung, manuelles Nachladen,
Schießen), SMG (Haltung, zwei- und einhändig), Schrotflinte, AR2, Magnum, Armbrust,
RPG (jeweils Nachladen und Schießen), Brechstange (Richtung, Nahkampfschaden),
Waffenwechsel Brechstange→SMG→Brechstange.

Einschränkungen, die im Status bleiben:
- Vollständige native Munitionsfolge ist **nur für die Pistole** protokolliert.
- Bildrate ist **noch nicht auf Hardware gemessen**. Die Instrumentierung ist fertig
  (`gquest_perf`), aber es liegt keine Frametime-Reihe von einem Quest-3-Lauf vor.
  Frühere Läufe lagen teils unter 72 Hz — das ist eine Beobachtung, keine Messung.

---

## 6. Quest-3S-Status

**NOT TESTED.**

Es existiert kein Lauf auf Quest 3S. Seit der Profiltrennung hat das Gerät eigene
Stufen (916×960 / 1374×1440 / 1558×1632, Empfehlung Ausgewogen bei 72 Hz), die der
Rust-Parser akzeptiert — aber keine davon wurde auf 3S-Hardware verifiziert. Das ist
ein Release-Blocker, kein Schönheitsfehler.

---

## 7. PCVR-Status

**NOT STARTED.**

Kein PC-Build, kein Windows-Host, keine OpenXR-Anbindung außerhalb von Android,
kein SteamVR-Test, kein Link/Air-Link-Test.

---

## 8. Crossplay-Status

**BLOCKED — architektonisch, nicht nur unimplementiert.**

GDroid existiert ausschließlich für Android/ARM64. Ohne PC-Build derselben
Engine-Familie gibt es keinen zweiten Endpunkt. Mögliche Wege und Risiken stehen in
`docs/MIGRATION_PLAN.md`, Phase 12. Bis ein Test zwischen zwei echten Geräten
bestanden ist, wird Crossplay als nicht verfügbar dokumentiert.

---

## 9. Bekannte Fehler und offene Risiken

| # | Punkt | Schwere | Status |
|---|---|---|---|
| K1 | 10+ hartkodierte VAs in `libclient.so` | kritisch | offen — bricht bei GDroid-Update |
| K2 | GOT-Patching von `liblauncher.so` | hoch | offen |
| K3 | 4-Byte-Patch in `libclient.so` | hoch | offen |
| K4 | `rtk proxy`-Build | mittel | **erledigt** — `--check`/`--tests`/Vollbuild ohne Wrapper |
| K5 | Duplikate `work/*` ↔ `Gquest-Hybrid/bridge/*` | mittel | offen |
| K6 | Lizenz am eigenen Code | mittel | **erledigt** — MIT, siehe `LICENSE` |
| K7 | Quest 3S ungetestet | hoch | offen |
| K8 | Nur Pistole hat native Munitions-Protokoll | mittel | offen |
| K9 | Keine Frametime-Messung | mittel | **Instrumentierung erledigt**, Hardware-Lauf offen |
| K10 | Linke Hand nutzt Original-Fingerpfad | niedrig | bewusst |

---

## 10. Nächste Aufgabe

**Phase 4 — Core-Skelett und Plattformabstraktion.** Voraussetzung: Entscheidung E1
(geteilter Core / nur Overlay / nur Neubau), weil sie den Schnitt festlegt.

Konkret als erstes Paket:

1. `core/platform/` mit `IPlatformHost`, `IVRBackend`, `IAssetSource`, `IClock`, `ILog`.
2. `core/vr/tracking` mit `PoseSnapshot` + `valid_mask` + `isfinite`-Gates — die
   Verhaltensvorgabe liefert der bereits laufende Test `vr_lua.cpp`.
3. `core/vr/playspace` mit Snap-/Smooth-Turn, Recenter, Seated/Standing.
4. Ein Fake-Host, der 60 Frames Posen liefert, ohne OpenXR, Android oder Engine.

Warum nicht „Build fertig“: Phase 3 ist bis auf die optionale Zusammenführung der
Spiegel-Dateien und den Rust-Pfad erledigt. Die Prüfbasis steht jetzt (11 Tests grün),
damit ist der nächste sinnvolle Schritt der Core-Schnitt.

---

## 11. Roadmap-Kurzfassung

```
Phase 1  Analyse ............................. DONE
Phase 2  Architektur (Entwurf) ............... DONE
Phase 3  Reproduzierbarer Build .............. ← nächste Aufgabe (blockiert)
Phase 4  Core-Skelett + Platform-Abstraktion . NOT STARTED
Phase 5  Core in Host GDroid einhängen ....... NOT STARTED
Phase 6  VR-Player, Hände, Interaktion ....... NOT STARTED
Phase 7  Sandbox + 3D-Spawn-Menü ............. NOT STARTED
Phase 8  Waffen/Tools in den Core ............ PARTIALLY (nur Overlay)
Phase 9  NPC/KI .............................. NOT STARTED
Phase 10 Fahrzeuge ........................... NOT STARTED
Phase 11 Multiplayer Quest↔Quest ............. NOT STARTED
Phase 12 Crossplay ........................... BLOCKED
Phase 13 Lua-Sandbox ......................... NOT STARTED
Phase 14 Modding ............................. NOT STARTED
Phase 15 Mod-Manager ......................... NOT STARTED
Phase 16 Workshop-Backend .................... NOT STARTED
Phase 17–19 Maps, Editor, Audio/Spatial UI ... NOT STARTED
Phase 20 Quest-Optimierung ................... NOT STARTED
Phase 21 PCVR-Host ........................... NOT STARTED
Phase 22 Security ............................ NOT STARTED
Phase 23 QA .................................. NOT STARTED
Phase 24 Release-Builds ...................... NOT STARTED
```

---

## 12. Offene Entscheidungen (Nutzer)

**E1** Grundstrategie: geteilter Core mit zwei Hosts / nur Overlay / nur Neubau.
**E2** Eigene Assets parallel aufbauen, damit das Spiel irgendwann ohne Retail-Inhalte
installierbar ist?
**E3** ~~Lizenz für den eigenen Code wählen~~ — **erledigt**: MIT (`LICENSE`), Herkunft und
zlib-Kennzeichnungspflicht in `THIRD_PARTY_NOTICES.md`. Offen bleibt nur die Bestätigung,
dass „shiftmann“ als Rechteinhaber-Name im Copyright-Header gewünscht ist.
**E4** GDroid 0.1.30 einfrieren oder neuen Versionen aktiv folgen?

Ohne E1 ist Phase 4 nicht sinnvoll beginnbar, weil sie den Schnitt festlegt.
