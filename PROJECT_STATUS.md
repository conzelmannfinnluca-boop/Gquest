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

- eigenem C++-Bridge (`liblauncheq.so`, 608 Zeilen, inkl. Geräteerkennung),
- eigener Rust-Startkomponente (366 Zeilen, 9 Tests),
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
| Rust-Startprofil + Launch-Argumente | DONE | 9 Unit-Tests im Code; Injection-Test vorhanden |
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
| Performance-HUD (Anzeige) | DONE | Overlay im `gquest_perf_hud.lua`; auf Hardware nicht gesichtet |
| Automatisierte Gerätetests | NOT STARTED | nur manuelle Trägerbestätigung |
| Performance-Sampler + CSV | DONE | `gquest_perf_hud.lua`, 9. Lua-Harness deckt Statistik und Ausgabe ab |
| Performance-Messung auf Quest 3 | NOT TESTED | Instrumentierung fertig, Hardware-Lauf steht aus |
| Geräteprofile Quest 3 / 3S | DONE | eigene Stufensätze, vom Runtime akzeptiert, im Menü wählbar |
| Geräteprofile auf Quest 3S | NOT TESTED | Stufen definiert, aber kein Lauf auf 3S-Hardware |
| Geräteerkennung (Klassifizierung) | DONE | `android.os.Build.MODEL`/`.DEVICE` → Geräte-ID, C++-Test hier ausgeführt |
| Erkennungs-Statuszeile + Umstellen-Knopf | DONE | drei Zustände, Textbudget und Knopf getestet; Derma-Rendering ungeprüft |
| Geräteerkennung (JNI auf Gerät) | PARTIALLY IMPLEMENTED | Aufrufpfad, Fehlerpfade und Referenzzählung gegen Mock-JNI geprüft (`tests/device_jni.cpp`); echtes `PackageManager`-Verhalten NOT TESTED |
| Reale `Build.MODEL`-Werte Quest 3/3S | NOT TESTED | Erfassungswerkzeug + Protokoll fertig, kein Gerät (`docs/measurements/device-identity.md`) |
| `com.oculus.supportedDevices` im Overlay | PARTIALLY IMPLEMENTED | Wert wird zusammengeführt statt verdoppelt und zurückgelesen; nie gegen die echte Basis-APK gelaufen |
| Posen-Dekodierung (Snapshot → Position/Winkel) | DONE | direkt host-getestet inkl. 60er-Fake-Source; echtes XR-Input auf Gerät NOT TESTED |
| Gepinnte Adressen vs. Audit-Datensatz | PARTIALLY IMPLEMENTED | Konstanten, Offsets und Abbildungsverschiebung geprüft; Segmentzugehörigkeit braucht `libclient.so` (NOT TESTED) |
| VR-Content-Installation (Manifest-Prüfung) | PARTIALLY IMPLEMENTED | Manifest-Regeln + Verzeichnisanlage host-getestet; `AAsset`-Pfad und Schreiben auf dem Gerät NOT TESTED |
| Widerspruch MODEL ↔ supportedDevices | DONE | Warnzeile im Log, reine Diagnose ohne Einfluss auf das Profil; auf Gerät NOT TESTED |
| Lizenz + Herkunftsnachweis | DONE | `LICENSE` (MIT), `THIRD_PARTY_NOTICES.md`, zlib-Volltext in `third_party/` |

---

## 3. Buildstatus

| Build | Status | Grund |
|---|---|---|
| `build.py --check` | **DONE** | meldet 9 Build- und 4 Test-Voraussetzungen + Spiegel-Drift, ohne Traceback; Fallbacks wie in den Läufen |
| `build.py --tests` | **DONE** | 9 C++ + 9 Rust + ABI-Smoke + Bridge-Cross-Compile + 4 Werkzeug-Selbsttests + 10 Lua |
| `build.py --units` | **DONE** | 9 C++ + 4 Werkzeug-Selbsttests in 5 Gruppen, ohne NDK/Rust/Lua; Exit 0/1 geprüft |
| `Gquest-Hybrid/tools/build.py` (Gesamt-APK) | **BLOCKED** | private Abhängigkeiten fehlen (bewusst) |
| Rust `cargo test` | **DONE** (9 von 9) | Toolchain lokal in `work/toolchains` installiert |
| C++-Grenztests | **DONE** (9 von 9) | siehe Abschnitt 4 |
| Lua-Harnesses (10) | **DONE** (10 von 10) | lokale Lua-5.4-Toolchain gebaut |
| C++/Rust-ABI-Smoke | **DONE** | `cargo build --release` + `ffi_smoke.cpp`, 6 Startfälle |
| Android-Bridge-Cross-Compile | **DONE** | `aarch64-linux-android29`, `-Wall -Wextra -Werror`, keine Warnung |
| `liblauncheq.so` linken + Overlay-APK | **BLOCKED** | braucht Basis-APK, JDK, Build-Tools |
| APK-Verifikation | **BLOCKED** | kein Basis-APK |

Fehlende, bewusst nicht versionierte Voraussetzungen: `outputs/GDroid-0.1.30.apk`,
`work/gdroid-0.1.30-native/`, `work/android-sdk/`, `work/toolchains/`,
`work/quest-vr-content/`, `work/quest-vr-content-manifest.json`, Debug-Keystore,
Spielinhalte. Der frühere `rtk proxy`-Wrapper ist entfernt; `build.py --check` listet
diese Dateien jetzt einzeln mit Zweck und Beschaffungsweg auf.

---

## 4. Teststatus (in dieser Sitzung tatsächlich ausgeführt)

Umgebung: Linux, `g++ 13.3.0`, `python3 3.12.3`, keine private APK. Lua 5.4.7 und eine
Rust-stable-Toolchain sowie ein NDK-Teil (clang 12.0.9 + Sysroot-Header) wurden lokal nach
`work/toolchains/` installiert (per `.gitignore` ausgeschlossen, Reinstallationsanleitung
in BUILD.md).

Ein Befehl, reproduzierbar:

```sh
python3 Gquest-Hybrid/tools/build.py --tests
```

Ergebnis: **9 C++-Grenztests, 9 Rust-Tests, C++/Rust-ABI-Smoke, Android-Bridge-Cross-Compile,
Auswertungs-, Erfassungs-, Manifest- und Adress-Selbsttest sowie 10 Lua-Harnesses
bestanden**, Exit-Code 0 — 34 Prüfungen.

Rust-Tests:
- Startargumente: Profil-Einstellungen und `+hlvr_isvrplayer` stehen vor `+map`, `-vr` an Index 1
- Alle sechs Gerätestufen parsen; Geräte- und Preset-Zeilen werden vom Runtime ignoriert
- Ungültige Profilwerte können keine Engine-Kommandos einschleusen (Injection-Test)
- CRLF und alle Auflösungsstufen bleiben erhalten
- Explizite Level-Kommandos (`+connect`, `+load`, `+changelevel`) werden nicht überschrieben
- FFI behandelt Nullzeiger, hält `argv` eigentümerrichtig und nullterminiert
- Geräteerkennung: eine frische Installation übernimmt die Empfehlung des erkannten Geräts; eine Stufe des anderen Headsets schnappt auf die Empfehlung; gleiches Gerät, unbekanntes Gerät und fehlende Erkennung lassen die Wahl unangetastet

C++-Grenztests:
- `PASS native finger wrapper: all profiles, left/root/flags untouched, original input interpolation, invalid/off passthrough`
- `PASS explicit native action sets: weapon/eject, both hands, missing set/action, inactive, invalid hand and embedded-NUL guards`
- `PASS VR Lua bridge: both hands/head/aim, quaternion axes, real validity/finite gates, input routing, inactive/invalid input and bounded haptics`
- `PASS ArcVR retirement: 63 owned files backed up, unrelated addon retained, repeated launch, backup collision and symlink guard`
- `PASS device model classification: 3S beats 3, case/whitespace/near-miss guards, codename fallback, nulls and stable ids`
- `PASS pose snapshot: metre-to-inch mapping with Y/Z swap, yaw/pitch axes, non-finite and out-of-window quaternions refused without a half-written result, 60 fake frames with 58 valid`
- `PASS readable memory: inside/at-edge accepted, PROT_NONE, spans across a mapping boundary, null and a wrapping length refused, zero length reports the address itself`
- `PASS content install: manifest rejects absolute paths, .. segments, non-numeric and overflowing sizes, empty paths and CRLF; directory creation is idempotent and refuses to descend into a file`
- `PASS device JNI readers: meta-data requested with GET_META_DATA, absent key and null bundle stay empty, throwing calls clear the exception, every local reference released`
- `PASS signature scan: unique hit at first byte, ambiguous duplicates and overlapping hits rejected, short prefix stops being decisive once it repeats, bad ranges not found, resolver fails closed with a reason`

Android-Bridge (Cross-Compile für aarch64-linux-android29):
- `PASS bridge cross-compiles for aarch64-linux-android29 (keine Warnung, -Werror)`
- Gegenprobe: ein absichtlich falscher JNI-Parameter bricht den Lauf mit der echten
  `jni.h`-Signatur ab — der Check prüft wirklich und ist nicht nur ein Compiler-Aufruf

Performance-Auswertung (`perf_report.py --test`, synthetische Daten):
- Urteile geeignet / grenzwertig / ungeeignet aus `ms_p95` gegen das Budget der Rate
- überlappende p95-Bereiche gelten als „nicht gezeigt", nie als „ungefähr gleich"
- Abbruch bei gemischten Bildwiederholraten in einer Gruppe statt stiller Mittelung
- Gegenprobe: eine absichtlich kaputte Rauschgrenze oder ein entferntes Grenzband
  lassen den Selbsttest scheitern — er prüft die Regel, nicht nur den Aufruf

Geräteerfassung (`capture_device.py --test`, Stub-adb statt Headset):
- Klassifizierung inklusive `Oculus_*`-Schreibweise, Fast-Treffer bleiben unbekannt
- `getprop`-Pfad und `DEVICE`-Logzeile werden gelesen, fehlender In-App-Wert wird benannt
- Urteil `konsistent` gegen `WIDERSPRUCH` bei abweichendem App-Wert
- Protokollzeile wird ersetzt statt angehängt (zweimal erfassen ⇒ eine Zeile)

Gepinnte Adressen (`pinned_addresses.py --test`, Audit-Datensatz + synthetische ELF-Header):
- relative Offsets der Bridge (`+0x224`, `+0x564`) stimmen mit den Audit-Adressen überein
- Code-Adressen liegen sämtlich unter den Daten-Globals, alle passen in 32 Bit
- `VA − Datei-Offset` des Patch-Eintrags ist seitenbündig (`0x4000`); ein falsch gepaartes
  Adresspaar ergibt `0x3fc4` und wird als Fehler gemeldet
- ELF-Programmheader-Leser klassifiziert Code als ausführbar und Globals als lesbar,
  lehnt abgeschnittene und fremde Dateien ab
- **Nicht geprüft:** die Zugehörigkeit zu den echten Segmenten — dafür fehlt `libclient.so`

Überlagerungs-Manifest (`overlay_manifest.py --test`, synthetische Manifeste):
- `com.oculus.supportedDevices` wird zurückgelesen statt angenommen
- Zusammenführen behält Reihenfolge, entfernt Duplikate, ergänzt fehlende IDs
- zwei Elemente werden als Fehler erkannt (Android behielte eines davon)
- unbekannte Geräte-IDs und Nicht-XML werden abgelehnt

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
- Geräteerkennung im Menü: Hinweisdatei lesen, Whitespace/CRLF tolerieren, unbekannte ID ignorieren, frische Installation auf dem erkannten Gerät starten, gespeichertes Profil nie überschreiben, Statuszeile für alle drei Zustände inklusive Textbudget je Gerätename, Umstellen auf das erkannte Gerät samt Empfehlung, Menü-Klick auf den Knopf
- Menü-Navigation: Root → Ausrichtung → Zurück → Schließen → Wiederöffnen → Waffen

Zusätzlich geprüft: `--check` meldet alle 9 fehlenden Voraussetzungen mit Zweck und
Beschaffungsweg; ohne `liblua5.4` meldet der Test-Modus `SKIPPED` statt `FAIL`.

**Nicht ausgeführt:** Linken von `liblauncheq.so`, Overlay-APK, APK-Verifikation, jeder
Hardware-Test, jede Frametime-Messung auf einem Headset. Diese Liste ist absichtlich vollständig — nichts
davon wird als bestanden behauptet.

---

### 4.1 Ungetestete Bridge-Teile (benannt, nicht still)

Die Bridge besteht aus 14 Funktionen. Vier haben eine Host-Abdeckung (drei davon teilweise),
eine ist trivial, und die übrigen neun hängen an geladenen Bibliotheken, EGL, einer
JNI-Laufzeit oder einem Gerätepfad. Diese Tabelle ist eine Aussage über die **Abdeckung**,
kein Urteil über die Qualität — sie existiert, damit eine Lücke nicht dadurch verschwindet,
dass niemand sie aufschreibt.

**Reihenfolge nach Risiko (Schaden × Häufigkeit).** Zuerst war `ReadableMemory` dran: sie
trägt **jede** gepinnte Speicherprüfung, ein falsches „lesbar" macht also aus einem
abgefangenen Fehler einen Schreibzugriff in fremden Speicher — und sie war als einzige
hostseitig vollständig prüfbar. Danach folgen `ConfigureQuestLeftPalm` (patcht laufenden
Code, opt-in, Rücknahme beim Shutdown) und `InstallInputSnapshotBridge` / `XRInputSnapshot`
(Vtable- bzw. Provider-Patch in `libvrxr`); beide brauchen das Gerät.

| Funktion | Aufgabe | Warum kein Host-Test | Was ein Test abdecken würde |
|---|---|---|---|
| `BridgeLog` | Logcat + Datei unter `/data/user/0/…` | `__android_log_print` und fester Gerätepfad | Trunkierung bei 1024 Zeichen, Formatfehler |
| `GquestScanLogToBridge` | eine Zeile, leitet Scan-Meldungen ins Log | trivial; Hook der getesteten Scan-Engine | – |
| `ConfigureQuestLeftPalm` | Signatursuche + Patch des Konstruktors (`+0x224`) im geladenen `libclient.so`, Rücknahme beim Shutdown | braucht den geladenen Client | Patch an/aus, Rücknahme, Fehlerpfad bei Drift |
| `ProbeQuestHandOffsets` | liest Instruktionen an gepinnten Daten-Globals (`0xf47ae0`, `0xf47948`, `0xf4e818`) | braucht den geladenen Client | gepinnte Offsets, Verhalten bei abweichender Build |
| `EnsureQuestLayerTargets` | patcht den Layer-Allokator (`0x3ed58c`) | braucht den geladenen Client | Patch-Sicherheit, Idempotenz |
| `QuestPollEvent` | leitet SDL-Events weiter, greift ins Menü ein | braucht die laufende Event-Schleife | Routing, Rückgabewerte, Weitergabe |
| `SharedCreateContext` | EGL-Context-Sharing beim Erzeugen | braucht EGL und `liblauncher` | Austausch der Kontexte, Fehlerpfade |
| `InstallContextSharing` | `dl_iterate_phdr`-Hook installiert den Wrapper | braucht die geladene Bibliothek | Auswahl des richtigen Moduls, Abbruch |
| `XRInputSnapshot` | Snapshot-Provider für `libvrxr` | wird nur von der XR-Bibliothek aufgerufen | Feldbelegung, Größen, ungültige Eingabe |
| `InstallInputSnapshotBridge` | Vtable-Patch in `libvrxr` | braucht die geladene Bibliothek | Patch nur bei passender Signatur |
| `InstallVRContent` | kopiert das VR-Content-Paket | Manifest-Regeln **sind** getestet; `AAssetManager` und das Schreiben brauchen Assets + schreibbares Ziel | Kopierschleife, `.quest-lab-part`-Rename, Größenvergleich |
| `ConfigureDetectedDevice` | Geräte-ID setzen, Hinweisdatei schreiben | JNI-Teil **ist** getestet; `gquest_device.txt` braucht den Gerätepfad | Dateiinhalt, Fehlerpfad ohne Schreibrecht |
| `LauncherMainAndroid` | Orchestrierung: `dlopen`/`dlsym`, Reihenfolge Gerät → Content → ABI → Start | braucht alle Bibliotheken gleichzeitig | Reihenfolge und jeder Abbruchpfad |

Wer eine dieser Funktionen ohne Gerät prüfbar macht, streicht sie hier — die Liste soll
kürzer werden, nicht vollständiger aussehen.

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
  Das Verfahren inklusive Auswertung und Entscheidungsregel steht in
  `docs/PERF_PROTOCOL.md`; durchgeführt wurde es nie.

---

## 6. Quest-3S-Status

**NOT TESTED.**

Es existiert kein Lauf auf Quest 3S. Seit der Profiltrennung hat das Gerät eigene
Stufen (916×960 / 1374×1440 / 1558×1632, Empfehlung Ausgewogen bei 72 Hz), die der
Rust-Parser akzeptiert — aber keine davon wurde auf 3S-Hardware verifiziert. Das ist
ein Release-Blocker, kein Schönheitsfehler.

Seit der Geräteerkennung wählt der Start die 3S-Empfehlung selbst, sobald
`android.os.Build.MODEL` das Gerät meldet. Das **Lesen** der Java-Felder ist hier
nicht ausführbar; nur die Klassifizierung dahinter ist getestet.

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
| K1 | Hartkodierte VAs in `libclient.so` | kritisch | **teilweise erledigt** — 4 Code-Stellen per Signatur-Scan (fail-closed), Daten-Globals weiter gepinnt |
| K2 | GOT-Patching von `liblauncher.so` | hoch | offen |
| K3 | 4-Byte-Patch in `libclient.so` | hoch | offen |
| K4 | `rtk proxy`-Build | mittel | **erledigt** — `--check`/`--tests`/Vollbuild ohne Wrapper |
| K5 | Duplikate `work/*` ↔ `Gquest-Hybrid/bridge/*` | mittel | offen |
| K6 | Lizenz am eigenen Code | mittel | **erledigt** — MIT, siehe `LICENSE` |
| K7 | Quest 3S ungetestet | hoch | offen — Profile und Erkennung vorhanden, Hardware fehlt |
| K8 | Nur Pistole hat native Munitions-Protokoll | mittel | offen |
| K9 | Keine Frametime-Messung | mittel | **Instrumentierung, Protokoll und Auswertung erledigt**, Hardware-Lauf offen (`docs/PERF_PROTOCOL.md`) |
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
Spiegel-Dateien und den Rust-Pfad erledigt. Die Prüfbasis steht jetzt (34 Prüfungen grün),
damit ist der nächste sinnvolle Schritt der Core-Schnitt.

**Stand:** Paket 2 (PoseSnapshot + `isfinite`/Norm-Gates) und Paket 4 (Fake-Source mit 60
Frames, ohne OpenXR/Android/Engine) sind als **E1-unabhängiger** Teil umgesetzt:
`bridge/gquest_pose_snapshot.h` + `tests/pose_snapshot.cpp`. Sie liegen bewusst in
`bridge/` und nicht in einem neuen `core/`-Baum, weil dessen Zuschnitt genau das ist, was
E1 festlegt — der Code ist in allen drei Varianten unverändert nutzbar. Paket 1
(`IPlatformHost`, `IVRBackend`, `IAssetSource`, `IClock`, `ILog`) und Paket 3 (Playspace)
warten auf E1.

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
