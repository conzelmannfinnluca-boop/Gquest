# GQuest V2 — Source Analysis

Stand: 14. November 2026
Phase: 1 (Repository-Analyse)
Status dieses Dokuments: **DONE** (Analyse). Enthält keine Behauptung, dass GQuest V2 bereits existiert.

Alle Aussagen unten sind aus tatsächlich gelesenem Code, aus vorhandenen Prüfprotokollen
oder aus dem geklonten Repository abgeleitet. Wo etwas nicht geprüft werden konnte, steht
das ausdrücklich dabei.

---

## 0. Zusammenfassung der drei Quellen

| Quelle | Was tatsächlich vorliegt | Umfang | Lizenz | Verwendbarkeit |
|---|---|---|---|---|
| Altes GQuest | Eigener C++/Rust/Lua-Integrationscode + Tests + Prüfprotokolle | 4.689 Zeilen eigener Code | **keine Lizenz vergeben** (PUBLISHING.md) | Ausgangsbasis, voll nutzbar (eigenes Projekt) |
| GDroid | **Nur README.md + .gitignore.** Kein Quellcode im Repository | 0 Zeilen Quellcode | keine (Binary-Distribution) | Nur als Binary-Ziel und Verhaltensreferenz |
| VRMod | Lua-Addon + Assets, **ohne** das native VR-Modul | 15.971 Zeilen Lua, 76 Dateien | zlib (Catse 2019 / Abyss-c0re 2025) | Lua-Konzepte und -Code adaptierbar mit Kennzeichnungspflicht |

**Die wichtigste Erkenntnis dieser Analyse:** Zwei der drei Quellen sind **nicht**
quelloffen an der Stelle, an der man sie gerne refaktorieren würde.

- GDroid ist ein geschlossenes ARM64-Binary. „GDroid refactoren“ ist technisch unmöglich.
  Es gibt nur zwei Optionen: binär patchen (was das alte GQuest tut) oder nicht verwenden.
- VRMods eigentliche VR-Schicht ist ein geschlossenes natives Modul
  (`gmcl_vrmod_win64.dll` / `gmcl_vrmod_linux64.dll`, vom Addon per `require("vrmod")`
  geladen). Im Repository liegt nur die Lua-Ebene, die dieses Modul aufruft.

Damit ist die im Master-Prompt angenommene Kette
„GDroid analysieren → übernehmen/refactoren → GQuest V2“ **so nicht durchführbar**.
Die realistische Kette ist in `docs/ARCHITECTURE_V2.md` und `docs/MIGRATION_PLAN.md`
beschrieben.

---

## 1. QUELLE 1 — GDroid (technische Android-/GMod-Basis)

Repository: <https://github.com/tinsarfal/GDroid> (geklont, `--depth 1`)

### 1.1 Was im Repository ist

```
gdroid/README.md
gdroid/.gitignore
```

Sonst nichts. Keine Engine, kein Gradle-Projekt, kein CMake, kein NDK-Code, keine
Renderer-Quellen. Die Distribution erfolgt ausschließlich als APK über die Releases-Seite.

### 1.2 Was aus README und aus dem alten GQuest über GDroid belegbar ist

| Bereich | Befund | Belegquelle |
|---|---|---|
| Engine | Source-Engine-Port, abgeleitet von nillerusr's Android-Source-Arbeit | GDroid-README „Credits“ |
| Zielplattform | Android ARM64 (`arm64-v8a`) und ARMv7 (`armeabi-v7a`), **Touch-Steuerung, kein VR** | GDroid-README |
| Rendering | GLES über SDL2 + EGL; natives `libshaderapidx9.so`, `libstudiorender.so`, `libmaterialsystem.so` | `work/gdroid-0.1.30-build-pin.json` |
| VR | **nicht in GDroid enthalten.** VR kommt aus der separat gepatchten Variante des alten GQuest (`libvrxr.so`, OpenXR-Loader) | `build-pin`, `quest_engine_bridge.cpp` |
| Build-System | geschlossen. Nur APK-Signatur/Hashes prüfbar, nicht reproduzierbar aus Quelle | `verify_gdroid_base.py` |
| Dateisystem | Spielinhalte in `/sdcard/srceng/{garrysmod,sourceengine,platform}`, VPK-basiert | GDroid-README |
| Input | Touch, Bluetooth-Controller, Tastatur/Maus; InputSystem-vtable | GDroid-README, `audit.md` |
| Netzwerk | Source-Engine-Netzwerk (Server autoritativ, kein eigener Netcode) | abgeleitet aus Engine-Familie, nicht separat geprüft |
| Addons | `.gma` / Ordner in `garrysmod/addons`, Steam-Workshop-Download | GDroid-README |
| Speicher | 32-bit-Adressraum-Grenzen bei ARMv7; ARM64 ohne gemessene Grenze | nicht geprüft |

### 1.3 Gepinnte Binary-Fakten (aus dem alten GQuest, verifizierbar)

- Basis-APK: `GDroid-0.1.30.apk`, SHA256
  `28bcce6d656f324b883fa638ceae2893cfa875e423f28a7fbc2329c5cdd5d13c`
- Paketname: `com.gmodvr.qvrx` (die GQuest-VR-Variante; das Flat-GDroid heißt `com.gmodvr.flat`)
- 34 native Bibliotheken mit Einzel-Hashes gepinnt (`work/gdroid-0.1.30-build-pin.json`)
- Genau **drei** bestehende APK-Einträge werden verändert:
  `AndroidManifest.xml` (VR-Intent-Filter, `debuggable`, Label), `classes.dex`
  (ein String `launcher` → `launcheq`), `lib/arm64-v8a/libclient.so`
  (4 Byte bei `0x54e128`: `mov w1,wzr` → `mov w1,#1`, VR-Player-Cvar beim Start)
- Alle übrigen Bibliotheken müssen byte-identisch zur offiziellen 0.1.30 bleiben —
  das erzwingt `tools/build.py` per Assertion.

### 1.4 Bekannte Einschränkungen von GDroid (für GQuest V2 relevant)

1. **Kein Quellcode** → keine Upstream-Fixes, keine Portierung, jede GDroid-Version
   bricht potenziell alle Bridge-Offsets.
2. **Kein PCVR.** GDroid existiert nur für Android. Damit ist Quest↔PCVR-Crossplay mit
   GDroid als beiden Enden architektonisch ausgeschlossen.
3. **Retail-Inhalte erforderlich.** Ohne eigene Steam-Kopie von Garry's Mod läuft nichts.
   GQuest V2 kann damit kein eigenständig installierbares Spiel ohne Fremdinhalte sein.
4. **Kein Zugriff auf Renderer-Interna** außer über gepatchte Symbole/Offsets.
5. **Quest 3S ungetestet** (nur Quest 3 ist hardwarebestätigt).

### 1.5 Entscheidung je Komponente

| Komponente | Entscheidung | Begründung |
|---|---|---|
| Engine (Binary) | **übernehmen, unverändert** | einzige funktionierende GMod-Laufzeit auf Quest |
| Rendering | **übernehmen** (GLES/EGL), nur Startparameter + EGL-Sharing anfassen | eigener Renderer wäre Neubau eines Jahrzehnts Arbeit |
| Android/ARM64-Paketierung | **erweitern** (eigene Overlay-Payload + `liblauncheq.so`) | funktioniert, ist verifiziert |
| OpenXR (`libvrxr.so`) | **übernehmen**, eigene Session darf nicht geöffnet werden | eine Session, ein Owner — bestätigt in `lib.rs`-Kommentar |
| InputSystem-Anbindung | **refactoren** (Vtable-Slot 464 → eigener Snapshot-Provider) | funktioniert, ist aber fragile Offset-Kopplung |
| Build-System | **neu entwickeln** (eigenes, reproduzierbares Overlay-Build) | aktuelles Build nur im privaten Ordner lauffähig |
| VR-Player-Patch in `libclient.so` | **ersetzen durch dokumentierte Variante** | 4-Byte-Patch ist dauerhaftes Risiko |
| Netzwerk | **nicht übernehmbar** | Source-Netcode, kein Hook für eigene Autorität |

---

## 2. QUELLE 2 — VRMod (funktionale VR-Referenz)

Repository: <https://github.com/Metastruct/vrmod> (geklont, 76 Dateien, 15.971 Zeilen Lua)

### 2.1 Lizenzlage (geprüft, nicht angenommen)

`LICENSE` = zlib-Style-Lizenz:

- Original: Copyright (c) 2019 **Catse**
- Verändert: Copyright (c) 2025 **Abyss-c0re**

Erlaubt ausdrücklich Nutzung, Veränderung und Weitergabe **auch kommerziell**, unter drei
Bedingungen:

1. Herkunft nicht falsch darstellen, nicht behaupten, man hätte es geschrieben.
2. **Veränderte Versionen müssen deutlich als verändert gekennzeichnet werden** und dürfen
   nicht als Original dargestellt werden.
3. Lizenztext darf nicht entfernt werden.

**Konsequenz für GQuest V2:** Adaption von Lua-Code ist zulässig, wenn (a) Catse und
Abyss-c0re in den Credits stehen, (b) jede übernommene Datei einen Kopfkommentar
„adapted from VRMod (zlib), altered by GQuest“ trägt, (c) der Lizenztext beiliegt.
Das native Modul (`gmcl_vrmod_*.dll`) ist **nicht** Teil des Repositories und damit
**nicht** verfügbar.

### 2.2 Architektur (aus dem Code abgeleitet)

**Zustandsmodell.** Ein globales `g_VR`-Table hält den gesamten VR-Zustand:
`tracking` (Posen), `input` / `changedInputs` (Aktionen), `origin` + `originAngle`
(Playspace-Transformation), `view` (Render-View), `net` (Fremdspieler-Frames),
`threePoints` / `sixPoints` (3-Punkt- bzw. 6-Punkt-Tracking).

**Rendering.** Kein eigener Renderer: das Modul liefert ein Shared Texture, Lua rendert
zwei `RenderView`-Aufrufe (links/rechts) in ein Render-Target und submitet es über
`VRMOD_SetSubmitTextureBounds`. Per-Eye-FOV und Aspekt kommen aus
`VRMOD_GetDisplayInfo`.

**Input.** Action-Manifest (`vrmod/vrmod_action_manifest.txt`) plus Action-Sets
`/actions/base`, `/actions/main`, `/actions/driving`. Aktionen heißen
`vector1_forward`, `vector2_walkdirection`, `boolean_jump`, `boolean_teleport` usw.
Kein Polling einzelner Tasten — sauberes Action-Modell.

**Lokomotion.** Smooth-Turn und Snap-Turn (45°, Schwelle 0.5, Deadzone-Reset),
Teleport mit Parabel-Trace über 17 Beams und **serverseitiger Validierung**
(`PlayerNoClip` bzw. ULib-Permission). Fahrzeug: Sitz-Attachment `vehicle_driver_eyes`,
Lenkrad-Greifen (`wheelGripped`), Bewegung auf `CreateMove`-Ebene.

**Hände und Pickup.** `vrmod_pickup`-Entity; Client sucht Ziel per Trace, Server prüft
Gewicht (`vrmod_pickup_weight`), Reichweite, NPC-Erlaubnis und setzt pro Spieler ein
`NWBool("vrmod_pickup_valid_for_<SteamID>")`, das 1×/s für einen 300-Unit-Radius
aktualisiert wird. Halos als Client-Feedback. Drop übergibt echte Handgeschwindigkeit.

**Physik-Hände.** Serverseitig zwei `base_anim`-Entities mit Sphere-/Box-Collision, die per
`ComputeShadowControl` der Handpose folgen. Kollisionsform wird je Waffe umgeschaltet.

**Charakterdarstellung.** Floating-Hands-Modell mit `BuildBonePositions`-Override,
pro Finger `LerpAngle` zwischen Open/Closed, in Fahrzeugen ausgeblendet, plus
Spiegel-Render-Target für Höhenkalibrierung.

**Netzwerk.** Eigener Pose-Kanal: pro Frame 10 Finger × 7 Bit, `characterYaw` auf 7 Bit
gecrushed, Posen als Vector/Angle, optional Waist + 2 Füße. Serverseitig Puffer mit
`vrmod_net_storedframes` = 15 und Interpolations-Delay 0.1–0.2 s. Rate-Limits über
`NetReceiveLimited` (Pickup 10/s, 400 Byte).

### 2.3 Relevante Konzepte — Bewertung für GQuest V2

| Konzept | Bewertung | Übernahmeempfehlung |
|---|---|---|
| `origin`/`originAngle`-Playspace-Modell | **gut**, minimal und korrekt für Roomscale + Snap-Turn | übernehmen als Kernabstraktion |
| Action-Manifest statt Tastenpolling | **gut**, Voraussetzung für Rebinding und Left-Handed | übernehmen |
| Shared-Texture-Submit an das Runtime-Modul | funktioniert nur mit VRMods Modul | **nicht** übernehmbar → eigene OpenXR-Compositor-Layer |
| Frame-Pose-Replikation mit Bit-Packing | gutes Kostenmodell, aber `O(Spieler²)` und SteamID als Key | Konzept übernehmen, Implementierung neu |
| Serverseitige Pickup-Validierung + NWBool-Cache | solide Autoritäts-Trennung | übernehmen |
| `ComputeShadowControl`-Physikhände | funktioniert, ist aber Engine-spezifisch | Konzept übernehmen |
| Snap-Turn über `Think`, Smooth-Turn über `PreRender` | vermischt Simulations- und Renderrate | **neu trennen** (Tick vs. Frame) |
| Halo-Feedback am Greifziel | gut für Usability | übernehmen |
| Interpolationspuffer 15 Frames | sinnvoll | übernehmen mit Zeitstempel-basierter Auswahl |

### 2.4 Schwächen, die GQuest V2 nicht erben darf

1. **Harte Modul-Versionskopplung** (`requiredModuleVersion` 21/23) — jeder Modulwechsel
   blockiert das Addon komplett.
2. **SteamID als Netzwerk-Key** — nicht portabel auf Quest/Crossplay-Identitäten.
3. **Keine Interest-Management-Ebene** außer dem 300-Unit-Radius für Pickup-Flags;
   Posen gehen an alle.
4. **Render- und Simulationslogik im selben Hook** (`RenderScene` macht Tracking, Input,
   Netzwerk und Rendern) — nicht testbar, nicht dediziert-serverfähig.
5. **Globale `g_VR`-Tabelle** als einziger Zustandsspeicher — kein sauberer Lifecycle.

---

## 3. QUELLE 3 — Altes GQuest (Ausgangsbasis)

Repository: <https://github.com/conzelmannfinnluca-boop/Gquest> (dieses Repository)

### 3.1 Architektur

Es gibt **keine eigene Engine**. Das alte GQuest ist ein Overlay:

```
GDroid-0.1.30.apk (fremd, geschlossen)
        │  + 4 Byte Patch in libclient.so
        │  + Manifest-/DEX-Anpassung
        ▼
liblauncheq.so  (eigener C++-Bridge, 552 Zeilen)
        │  ├─ lädt liblauncher.so (Original) und libvrxr.so (OpenXR)
        │  ├─ installiert VR-Content aus APK-Assets
        │  ├─ bootstrapped XR-Session selbst
        │  ├─ patcht GOT-Einträge von liblauncher.so (SDL_GL_CreateContext, SDL_PollEvent)
        │  ├─ patcht InputSystem-Vtable-Slot 464
        │  ├─ registriert eigenes GLua-Modul `gquest_vr`
        │  └─ ruft Original-LauncherMainAndroid
        ▼
libgquest_runtime.a  (Rust, 210 Zeilen) — Startup-Argumente + VR-Profil
        ▼
Lua-Overlay (~1.090 Zeilen) in garrysmod/addons
```

### 3.2 Komponenten im Einzelnen

#### Rust (`Gquest-Hybrid/src/lib.rs`, 210 Zeilen) — **DONE, 5 Tests**

- `GquestProfile`: ABI 1, `eye_width/height`, `foveation`, `refresh_rate`, `profile_loaded`.
  Default 1032×1104 (Quest 3), zusätzlich 1548×1656 und 1680×1760.
- Liest `/sdcard/.../garrysmod/data/gquest_vr_profile.txt`, max. 4097 Byte, strikt
  zeilenweise. Ungültige Werte fallen auf Defaults — Test
  `invalid_profile_cannot_inject_engine_commands` belegt, dass Kommando-Injection
  (`1680x1760;quit`) nicht durchkommt.
- `launch_args()`: setzt `-vr` an Index 1, schiebt VR-Defaults **vor** `+map`,
  setzt `+hlvr_isvrplayer 1`, hängt `+map gm_construct` nur an, wenn kein
  `+map/+connect/+load/+changelevel` vorhanden ist.
- C-ABI: `gquest_runtime_create/destroy/profile/argc/argv`, `catch_unwind` an jeder
  Grenze, `argc` auf 0..=256 begrenzt, Strings auf 4096 Byte.
- **Wiederverwendbar: ja, unverändert.** Das ist der sauberste Teil des Projekts.

#### C++-Bridge (`Gquest-Hybrid/bridge/quest_engine_bridge.cpp`, 552 Zeilen)

| Funktion | Zweck | Status |
|---|---|---|
| `LauncherMainAndroid` | JNI-Einstiegspunkt, ersetzt `liblauncher.so`-Export | DONE (auf Quest 3 gelaufen) |
| `InstallVRContent` | Liest `quest_lab_vr_content.tsv`, schreibt Assets nach `vr_content/`, Größenprüfung, Pfad-Traversal-Schutz, atomares `rename` | DONE |
| `RetireGquestArcVR` | Verschiebt genau 63 alte ArcVR-Dateien in Backup, `lstat`-basiert, folgt keinen Symlinks | DONE, C++-Test vorhanden |
| `SharedCreateContext` / `InstallContextSharing` | Erzeugt Bootstrap-EGL-Context, teilt ihn dem Engine-Context, patcht dafür **nur** zwei GOT-Einträge in `liblauncher.so` | DONE, aber fragil |
| `QuestPollEvent` | Pro Frame: Layer-Targets, Left-Palm, Hand-Probe, Finger-Hook | DONE |
| `InstallInputSnapshotBridge` | Ersetzt InputSystem-Vtable-Slot 464 durch `XRInputSnapshot` (4288-Byte-Snapshot von `VRXR_LocateInput(0, …)`) | DONE, mit Stub-Byte-Prüfung |
| `EnsureQuestLayerTargets` | Ruft `layer_allocator` (VA `0x3ed58c`) einmal manuell, weil Render-Targets fehlen | DONE, mit Signaturprüfung |
| `ConfigureQuestLeftPalm` | Optionaler 1-Instruktions-Patch bei `0x46ece8` (`mov w5,w19` → `mov w5,#0`) | DONE, opt-in per Datei |
| `ProbeQuestHandOffsets` | 6 begrenzte Diagnose-Samples der lokalen Handpose | DONE (Diagnose) |
| `EnsureContentDirectory` | `mkdir -p` mit Typ-Prüfung | DONE |

Sicherheitsniveau der Bridge ist für ein Hobby-Projekt **überdurchschnittlich**:
jede Code-Patch-Stelle wird vorher per Byte-Signatur geprüft, bei Abweichung wird
**nicht** geschrieben, `mprotect` wird auf die aus `/proc/self/maps` gelesenen
Originalrechte zurückgesetzt, `MAP_FIXED_NOREPLACE` verhindert das Verdrängen fremder
Mappings, Trampoline werden auf ±128 MiB geprüft.

#### Native Finger-Profile (`bridge/gquest_native_finger_profiles.h`)

12 Profile (7 HL2-Waffen + Physgun + Werkzeuge), je 15 Finger × 3 Achsen × 2 Zustände
(open/closed) = 180 Byte pro Profil. Der Hook ersetzt **nur** die Eingabewerte des
nativen Finger-Blends an `0x46ed18` → Funktion `0x46e7b4`; linke Hand, Palm/Root und
Grasp-Flags bleiben beim Original. **DONE, C++-Test deckt alle Profile + Passthrough ab.**

#### VR-Lua-Kompatibilitätsmodul (`bridge/gquest_vr_lua.h`, 170 Zeilen)

Registriert `gquest_vr` als GLua-Native-Modul gegen die **vorhandene**
`liblua_shared.so` (kein eigener Lua-Interpreter). API:

```
vr.IsActive()
vr.GetHeadPose()            -> Vector, Angle, bool
vr.GetHandPose(hand)        -> Vector, Angle, bool
vr.GetAimPose(hand)         -> Vector, Angle, bool
vr.GetPrimaryHand() / vr.SetPrimaryHand(hand)
vr.GetAnalog(name, hand)    -> x, y, enabled
vr.GetDigital(name, hand)   -> down, changed, enabled
vr.GetActionDigital(set, action, hand) -> down, changed, enabled
vr.TriggerHaptic(hand, seconds, frequency, amplitude)
```

Technische Details, die erhalten bleiben müssen:
Positionsumrechnung `(x, -z, y) * 39.370098` (Meter → Source-Units),
Quaternion → Euler mit `asin` / `atan2`, Pose-Offsets im Snapshot
`8` (Head), `64 + 56*side` (Hand), `176 + 56*side` (Aim), Flag-Bit `4` bei
`116 + 56*side` bzw. `228 + 56*side`. **DONE, C++-Test deckt beide Hände, Achsen,
NaN-Gates, ungültige Hand-Indizes, eingebettete NULs und Haptik-Clamping ab.**

#### Lua-Overlay (`work/gquest-ui/lua/autorun/`)

| Datei | Zeilen | Aufgabe | Status |
|---|---|---|---|
| `gquest_00_vr_api.lua` | 7 | lädt `gquest_vr` als `vr`-Tabelle | DONE |
| `gquest_01_weapon_policy.lua` | 3 | verhindert Mod-Worldmodel-Override | DONE |
| `gquest_native_weapon_pose.lua` | 31 | schreibt erlaubte Waffenklasse in Datei für den Native-Hook | DONE |
| `gquest_wrist_hud.lua` | 48 | Tracking-Provider `GquestXR.GetWorldTracking()`; Wrist-HUD entfernt | DONE (HUD bewusst entfernt) |
| `gquest_reload.lua` | 72 | Manuelles Nachladen als Default, optionale Assisted-Refill | DONE |
| `gquest_weapon_catalog.lua` | – | Waffenkatalog | DONE |
| `gquest_weapon_models.lua` | 297 | VR-Modellzuweisung nach Deploy | DONE |
| `gquest_weapon_align.lua` | 392 | Griff-/Mündungs-Caches aus Modell-Attachments | DONE |
| `gquest_vr_ui.lua` | 225 | VR-Menü | DONE (Nutzer bestätigt) |
| `server/gquest_hl2_equipment.lua` | – | Ausrüstung + Reserve-Transfer mit Rollback | DONE |
| `server/gquest_hl2_models.lua` | – | Server-Modellzuweisung | DONE |

Wichtige Designentscheidung, die erhalten bleiben soll: `gquest_hl2_equipment.lua`
**erfindet keinen Munitionszustand**. Es verschiebt nur Reservemunition in ein
tatsächlich verlinktes natives Magazin, prüft per Readback und rollt bei Abweichung
zurück. Kammer und Slide bleiben Engine-Eigentum.

### 3.3 Tests (Bestand)

| Test | Art | Läuft ohne private Abhängigkeiten? |
|---|---|---|
| 5 Rust-Unit-Tests | `cargo test` | nein (Cargo fehlt im Repo-Export) |
| `native_fingers.cpp` | C++ Grenztest | **ja** |
| `vr_lua.cpp` | C++ Grenztest | **ja** |
| `retired_content.cpp` | C++ Grenztest | **ja** |
| `ffi_smoke.cpp` | C++/Rust-ABI | nein (braucht `libgquest_runtime.a`) |
| 8 Lua-Harnesses | Lua 5.4 via ctypes | nein (kein Lua im Container) |
| `verify_gdroid_base.py` | Hash-/Signatur-/ELF-Prüfung | nein (kein Basis-APK) |
| `verify_gquest_package.py` | APK-Payload-Identität | nein (kein APK) |

### 3.4 Build-Probleme (konkret)

`tools/build.py` bricht ohne diese **nicht im Repository enthaltenen** Dateien ab:

1. `outputs/GDroid-0.1.30.apk` (geschlossene Fremd-APK)
2. `work/gdroid-0.1.30-native/*.so` (34 Bibliotheken)
3. `work/android-sdk/` (NDK 23.2.8568313, build-tools 34.0.0)
4. `work/toolchains/` (JDK, cargo/rustup)
5. `work/quest-vr-content-manifest.json` + `work/quest-vr-content/`
6. `~/.android/debug.keystore`
7. Spielinhalte (`GQUEST_GAME_DIR`) für den Modell-Konverter

Der frühere Build rief zusätzlich `rtk proxy python3` auf — ein Wrapper, der außerhalb
der privaten Umgebung nicht existiert. **Das ist inzwischen behoben:** der Wrapper ist
entfernt, `build.py --check` listet alle fehlenden Dateien mit Zweck und Beschaffungsweg,
und `build.py --tests` führt 3 C++-Grenztests sowie 8 Lua-Harnesses ohne private Daten
aus. **Ergebnis: ein frischer Clone kann prüfen, aber kein APK bauen.** Der APK-Build
bleibt an den privaten Dateien hängen — eine bewusste Rechteentscheidung
(keine Fremdinhalte im Repo), kein Defekt.

### 3.5 Quest-3- und Quest-3S-Lage

- **Quest 3: PARTIALLY IMPLEMENTED + hardwarebestätigt** für Kopf/Controller/Hände,
  Menü, Pistole, SMG, Schrotflinte, AR2, Magnum, Armbrust, RPG, Brechstange.
- **Quest 3S: NOT TESTED.** Es existiert kein eigener Lauf. Inzwischen hat das Gerät
  eigene Auflösungsstufen (916×960 / 1374×1440 / 1558×1632), die der Rust-Parser
  akzeptiert; auf 3S-Hardware verifiziert ist davon nichts.
- Native Munitions-/Kammer-Übergänge sind **nur für die Pistole** vollständig
  protokolliert (`docs/Gquest-HL2-reload-verification.json`); für die anderen sechs
  Waffen existiert nur die Trägerbestätigung.

### 3.6 Technische Schulden (priorisiert)

| # | Schuld | Risiko | Empfehlung |
|---|---|---|---|
| T1 | 10+ hartcodierte VAs in `libclient.so` | kritisch — bricht bei jedem GDroid-Update | **teilweise erledigt**: vier Code-Stellen werden per Byte-Signatur gesucht (`gquest_signature.h`), kein/mehrdeutiger Treffer bricht ab; GOT-/BSS-Globals bleiben gepinnt |
| T2 | GOT-Patching von `liblauncher.so` | hoch | durch dokumentierte Launcher-Argumente ersetzen, wo möglich |
| T3 | 4-Byte-Patch in `libclient.so` im APK | hoch | Alternative: Cvar nach Init per eigenem Code setzen |
| T4 | `rtk proxy`-Build-Wrapper | mittel | **behoben** — direkte `python3`-Aufrufe, `--check`/`--tests` |
| T5 | Keine Lizenz für eigenen Code | mittel | Lizenz wählen, bevor Inhalte Dritter aufgenommen werden |
| T6 | Duplizierte Dateien `work/*` ↔ `Gquest-Hybrid/bridge/*` | mittel | eine Quelle, Symlink oder Generierung |
| T7 | Lua-Harnesses brauchen Lua 5.4 | niedrig | **behoben** — lokaler Lua-Build dokumentiert, alle 8 laufen |
| T8 | Zustand in globalem `GquestXR`-Table | mittel | Lifecycle + explizite Objekte |
| T9 | `gquest_weapon_align.lua` mit 392 Zeilen in einer Datei | niedrig | bei V2 aufteilen |
| T10 | Keine Quest-3S-Messung | hoch für Release | eigener Hardware-Lauf + Frametime-Protokoll |

### 3.7 Wiederverwendbarer Code — konkret

**Unverändert übernehmen:**
- `src/lib.rs` (Rust-Profil + Launch-Argumente) inkl. Tests
- `bridge/gquest_vr_lua.h` (VR-Lua-API) inkl. Test
- `bridge/gquest_native_finger_profiles.h` (Profiltabelle) inkl. Test
- `bridge/gquest_retired_content.h` (Migrationsliste) inkl. Test

**Refactoren:**
- `quest_engine_bridge.cpp` → in Module trennen
  (`content_install`, `xr_session`, `egl_share`, `input_bridge`, `native_hooks`)
- Lua `gquest_weapon_align.lua` → `weapon/align`, `weapon/muzzle`, `weapon/grip`
- Build-Pipeline → portabel, mit klaren Fehlermeldungen pro fehlender Abhängigkeit

**Neu entwickeln:**
- Engine-agnostischer GQuest Core (siehe `ARCHITECTURE_V2.md`)
- Eigene Netzwerkschicht mit Server-Autorität
- Lua-Sandbox mit Permission-System (die Engine-Lua ist **nicht** sandboxed)
- Save-/Map-/Mod-System
- PCVR-Host und Crossplay-Transport

### 3.8 Was das alte GQuest ausdrücklich **nicht** hat

Damit PROJECT_STATUS ehrlich bleibt: es existiert **kein** Code für
NPC-/KI-System, Fahrzeugsystem, eigenes Physiksystem, Sandbox-Objektmodell,
Undo/Redo, Multiplayer-eigener Netcode, Crossplay, Dedicated Server, PCVR-Build,
Map-Editor, Workshop-Backend, Mod-Manager, Save-System, Spatial-UI-Framework,
Performance-HUD, Permission-System oder automatisierte Gerätetests.

Der Master-Prompt beschreibt diese als Ziele. Sie sind **nicht** vorhanden.

---

## 4. Quellenübergreifende Risiken

| Risiko | Auswirkung | Gegenmaßnahme |
|---|---|---|
| GDroid-Update ändert Offsets | Bridge startet nicht mehr | Signatur-Scan + Fail-Closed (bereits vorhanden) + Versionserkennung |
| Retail-Inhalte nötig | keine eigenständige Distribution | eigenes Asset-Paket für GQuest-eigene Inhalte planen |
| Keine Lizenz am eigenen Code | keine Beitragenden, keine Workshop-Distribution | Lizenz + CLA vor Öffnung |
| zlib-Kennzeichnungspflicht bei VRMod-Adoption | Lizenzverstoß bei unmarkierter Kopie | Kopfkommentar + Credits + Lizenztext |
| Quest-3S ungetestet | Release-Blocker | eigener Testlauf, Performance-Profil |
| Eine OpenXR-Session, ein Owner | doppelte Session = Crash | Core öffnet **nie** eine Session, nur der Host |

---

## 5. Fazit der Analyse

1. Das alte GQuest ist **die einzige echte Substanz** — 4.689 Zeilen eigener Code mit
   Hardware-Bestätigung auf Quest 3.
2. GDroid ist **nur als Binary** nutzbar. „Refactoren“ entfällt; nur Patchen oder Ersetzen.
3. VRMod ist **Lua-Referenz mit zlib-Lizenz**, deren native VR-Schicht fehlt. Adaption
   ist erlaubt und sinnvoll für Konzepte (Playspace, Action-Model, Pickup-Autorität),
   nicht für Rendering.
4. Der Weg zu einem eigenständigen GQuest V2 führt **nicht** über ein Refactoring von
   GDroid, sondern über einen engine-agnostischen Core mit zwei Hosts. Details:
   `docs/ARCHITECTURE_V2.md`, Reihenfolge: `docs/MIGRATION_PLAN.md`.
