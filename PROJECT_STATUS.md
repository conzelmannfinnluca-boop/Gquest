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
| Lizenz + Herkunftsnachweis | DONE | `LICENSE` (MIT), `THIRD_PARTY_NOTICES.md`, zlib-Volltext in `third_party/` |

---

## 3. Buildstatus

| Build | Status | Grund |
|---|---|---|
| `Gquest-Hybrid/tools/build.py` (Gesamt-APK) | **BLOCKED** | private Abhängigkeiten fehlen |
| Rust `cargo test` | **BLOCKED** | kein `cargo` im Export/Container |
| C++-Grenztests | **DONE** (3 von 3 ausführbaren) | siehe Abschnitt 4 |
| C++/Rust-ABI-Smoke | **BLOCKED** | braucht `libgquest_runtime.a` |
| Lua-Harnesses (8) | **BLOCKED** | kein Lua 5.4 im Container |
| APK-Verifikation | **BLOCKED** | kein Basis-APK |

Fehlende, bewusst nicht versionierte Voraussetzungen: `outputs/GDroid-0.1.30.apk`,
`work/gdroid-0.1.30-native/`, `work/android-sdk/`, `work/toolchains/`,
`work/quest-vr-content/`, `work/quest-vr-content-manifest.json`, Debug-Keystore,
Spielinhalte. Zusätzlich ruft der Build `rtk proxy` auf, das außerhalb der privaten
Umgebung nicht existiert.

---

## 4. Teststatus (in dieser Sitzung tatsächlich ausgeführt)

Umgebung: Linux, `g++ 13.3.0`, `python3 3.12.3`, **kein** cargo, **kein** Lua,
**keine** private APK.

```
c++ -std=c++17 -O2 -I Gquest-Hybrid/bridge tests/native_fingers.cpp  -ldl  → PASS
c++ -std=c++17 -O2 -I Gquest-Hybrid/bridge tests/vr_lua.cpp          -ldl  → PASS
c++ -std=c++17 -O2 -I Gquest-Hybrid/bridge tests/retired_content.cpp       → PASS
```

Ausgaben:
- `PASS native finger wrapper: all profiles, left/root/flags untouched, original input interpolation, invalid/off passthrough`
- `PASS explicit native action sets: weapon/eject, both hands, missing set/action, inactive, invalid hand and embedded-NUL guards`
- `PASS VR Lua bridge: both hands/head/aim, quaternion axes, real validity/finite gates, input routing, inactive/invalid input and bounded haptics`
- `PASS ArcVR retirement: 63 owned files backed up, unrelated addon retained, repeated launch, backup collision and symlink guard`

**Nicht ausgeführt:** Rust-Tests, alle 8 Lua-Harnesses, ABI-Smoke, APK-Verifikation,
jeder Hardware-Test, jede Frametime-Messung. Diese Liste ist absichtlich vollständig —
nichts davon wird als bestanden behauptet.

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
- Bildrate ist nicht systematisch gemessen (72-Hz-Profil gesetzt, frühere Läufe teils
  darunter — keine Zahl belegbar).
- Kein Performance-HUD, keine Frametime-Reihe.

---

## 6. Quest-3S-Status

**NOT TESTED.**

Es existiert kein Lauf auf Quest 3S. Die Zielauflösung 1548×1656 ist im Rust-Profil
vorgesehen, aber nie auf Hardware verifiziert. Das ist ein Release-Blocker, kein
Schönheitsfehler.

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
| K4 | `rtk proxy`-Build | mittel | offen (Phase 3) |
| K5 | Duplikate `work/*` ↔ `Gquest-Hybrid/bridge/*` | mittel | offen |
| K6 | Lizenz am eigenen Code | mittel | **erledigt** — MIT, siehe `LICENSE` |
| K7 | Quest 3S ungetestet | hoch | offen |
| K8 | Nur Pistole hat native Munitions-Protokoll | mittel | offen |
| K9 | Keine Frametime-Messung | mittel | offen |
| K10 | Linke Hand nutzt Original-Fingerpfad | niedrig | bewusst |

---

## 10. Nächste Aufgabe

**Phase 3 — Build-Reproduzierbarkeit herstellen.** Konkret:

1. `Gquest-Hybrid/tools/build.py` ohne `rtk proxy` aufrufbar machen.
2. Fehlende Voraussetzungen als geprüfte Vorbedingung mit verständlicher Meldung
   abfangen (Pfad, Zweck, Beschaffung).
3. Lua 5.4 in den Test-Pfad bringen, damit die 8 vorhandenen Harnesses laufen.
4. C++-Grenztests in ein einzelnes Testziel fassen.

Warum diese und nicht eine „spannendere“: ohne lauffähige Core-Tests ist keine weitere
Phase überprüfbar, und der Master-Prompt verlangt ausdrücklich echte, ausgeführte Tests.

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
