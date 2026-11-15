# GQuest V2 — Migrationsplan

Stand: 14. November 2026
Status: **Plan.** Die Phasen unten sind Arbeitsaufträge, keine Ergebnisse.
Abgeschlossen ist bisher ausschließlich Phase 1 (Analyse) und der Entwurf der Architektur.

Grundlage: `docs/SOURCE_ANALYSIS.md`, `docs/ARCHITECTURE_V2.md`.

---

## 1. Migrationsprinzipien

1. **Nichts funktionierendes wegwerfen.** Was auf Quest 3 hardwarebestätigt ist, bleibt
   in Betrieb, bis ein Ersatz nachweislich besser ist.
2. **Keine Regression im laufenden Overlay.** Jede Core-Extraktion ist ein eigener
   Commit mit eigenem Test.
3. **Fail-Closed bei nativen Eingriffen.** Signaturprüfung vor jedem Patch; bei
   Abweichung lieber nicht starten als falsch laufen.
4. **Zwei getrennte Builds.** Core-Tests müssen ohne Engine, ohne Android-SDK und ohne
   private APK laufen. Wer eine Fremd-APK zum Testen braucht, hat den Schnitt falsch
   gezogen.
5. **Jede Aussage hat einen Status.** DONE / IN DEVELOPMENT / PARTIALLY IMPLEMENTED /
   BLOCKED / NOT TESTED / FAILED.

---

## 2. Übernahme-Matrix (Quelle → Ziel)

| Bestandteil | Herkunft | Aktion | Zielort | Aufwand |
|---|---|---|---|---|
| Rust-Profil + Launch-Argumente | altes GQuest | **übernehmen, unverändert** | `host_gdroid/startup/` | S |
| VR-Lua-API (`gquest_vr_lua.h`) | altes GQuest | **übernehmen**, später auf Core-`IVRBackend` mappen | `host_gdroid/vrlua/` | S |
| Native-Finger-Profiltabelle | altes GQuest | **übernehmen, unverändert** | `host_gdroid/hooks/fingers/` | S |
| ArcVR-Retirement-Liste | altes GQuest | **übernehmen, unverändert** | `host_gdroid/migrate/` | S |
| Content-Installation (TSV + Assets) | altes GQuest | **refactoren** in eigenes Modul | `host_gdroid/content/` | M |
| EGL-Context-Sharing (GOT-Patch) | altes GQuest | **refactoren**, dokumentieren | `host_gdroid/egl/` | M |
| InputSystem-Vtable-Bridge | altes GQuest | **refactoren** auf Offset-Scan | `host_gdroid/input/` | M |
| Left-Palm-Patch | altes GQuest | **ersetzen** durch Argumentvariante prüfen | `host_gdroid/hooks/` | S |
| HL2-Griff-/Mündungs-Lua | altes GQuest | **refactoren** (392 Zeilen → 3 Dateien) | `host_gdroid/lua/weapon/` | M |
| Reload-Logik (manuell/assisted) | altes GQuest | **übernehmen**, Semantik in Core-Waffenmodell spiegeln | `core/weapons` + `host_gdroid/lua` | M |
| VR-Menü (`gquest_vr_ui.lua`) | altes GQuest | **refactoren** auf Spatial-UI-Framework | `core/ui` + Host-Renderer | L |
| Playspace-Modell (origin/originAngle) | VRMod | **Konzept übernehmen**, neu implementieren | `core/vr/playspace` | M |
| Action-Manifest-Modell | VRMod | **Konzept übernehmen** | `core/vr/input` | M |
| Pickup-Autorität (Gewicht, NWBool-Cache) | VRMod | **Konzept übernehmen**, mit `PlayerId` + Constraints | `core/net/authority` | M |
| Physik-Hände (`ComputeShadowControl`) | VRMod | **Konzept übernehmen** | `core/physics` + Host | M |
| Frame-Pose-Replikation (Bit-Packing) | VRMod | **neu implementieren** mit Zeitstempel + Delta | `core/net/protocol` | L |
| Rendering-Ansatz (Shared Texture) | VRMod | **verwerfen** | – | – |
| Lua-Code im Original | VRMod | **nicht kopieren**, nur Konzepte; bei späterer Übernahme zlib-Kopf + Credits | – | – |
| Engine/Renderer/Physik | GDroid | **unverändert nutzen** | `host_gdroid/native` | – |
| Netcode | GDroid | **nicht nutzbar**, Core baut eigenen | `core/net` | XL |
| PCVR-Host | – | **neu entwickeln** | `host_native/` | XL |
| Lua-Sandbox + Permissions | – | **neu entwickeln** | `core/lua` | L |
| Save/Map/Mod/Workshop | – | **neu entwickeln** | `core/{save,modding}` | L–XL |

Aufwandsschätzung: S ≤ 1 Tag, M ≤ 1 Woche, L ≤ 1 Monat, XL > 1 Monat (jeweils für
eine erfahrene Einzelperson; keine Kalenderzusage).

---

## 3. Phasen

### Phase 1 — Repository-Analyse — **DONE**

Erzeugnisse: `docs/SOURCE_ANALYSIS.md`, `docs/ARCHITECTURE_V2.md`,
`docs/MIGRATION_PLAN.md`, `PROJECT_STATUS.md`.

Akzeptanz: alle drei Quellen geprüft, Lizenzlage belegt, Wiederverwendbarkeit je
Komponente entschieden, Build-Blocker benannt.

---

### Phase 2 — Architekturentscheidung — **DONE (Entwurf)**

Erzeugnis: `docs/ARCHITECTURE_V2.md`, ADR-1 … ADR-10.

Offen: ADR-1 formal bestätigen (siehe Abschnitt 6, „Kritische Entscheidungen“).

---

### Phase 3 — Build-Reproduzierbarkeit herstellen — **DONE** (bis auf zwei Punkte)

Ziel: Tests laufen ohne private Abhängigkeiten, fehlende Dateien erzeugen eine
verständliche Meldung statt eines Tracebacks.

Erledigt:
1. `rtk proxy` ist aus Build, README und BUILD.md entfernt; `python3` genügt.
2. `build.py --check` meldet jede fehlende Voraussetzung mit Pfad, Zweck und
   Beschaffungsweg; Exit-Code 1, kein Traceback.
3. Lua 5.4 wird für die Harnesses lokal gebaut; alle **10 Lua-Harnesses bestehen**.
   Eine lokale Rust-Toolchain bringt zusätzlich die **6 Rust-Unit-Tests** zum Laufen.
4. `build.py --tests` fasst 3 C++-Grenztests + 6 Rust-Tests + 10 Lua-Harnesses in ein Testziel,
   Exit-Code 0, ohne private Daten.
5. `cargo.py` fällt auf ein System-`cargo` zurück und nennt sonst beide Suchpfade.
6. Spiegel-Drift `work/` ↔ `Gquest-Hybrid/bridge/` wird bei jedem Build geprüft
   (byte-identisch); die Dateien bleiben bewusst an beiden Pfaden, damit alle
   vorhandenen Build- und Prüfskripte unverändert funktionieren.

Offen (nicht blockierend):
- C++/Rust-ABI-Smoke hängt am `--release`-Build; der läuft nur im Gesamtbuild.
- Der volle APK-Build bleibt an Basis-APK, NDK, JDK und Signaturschlüssel gebunden
  (bewusst, siehe Lizenzlage).

Akzeptanz erfüllt: frischer Clone `⇒` `--check` und `--tests` laufen; der APK-Build
scheitert mit einer vollständigen Liste statt mit einem Traceback.

---

### Phase 4 — Core-Skelett und Plattformabstraktion — **NOT STARTED**

Ziel: `core/` mit `platform/`, `math/`, `vr/tracking`, `vr/playspace` und Unit-Tests,
baubar ohne Engine.

Aufgaben:
1. `IPlatformHost`, `IVRBackend`, `IAssetSource`, `IClock`, `ILog`.
2. `PoseSnapshot` mit `valid_mask` und `isfinite`-Gates (Logik aus `vr_lua.cpp`
   übernehmen — die Tests existieren bereits und definieren das Verhalten).
3. `Playspace` mit Snap-/Smooth-Turn, Recenter, Seated/Standing.
4. CI-Regel: `core/` darf keine Engine-Header inkludieren.

Akzeptanz: `./gq test core` grün; ein Fake-Host kann 60 Frames Posen liefern, ohne dass
OpenXR, Android oder die Engine vorhanden sind.

---

### Phase 5 — Core in Host GDroid einhängen — **NOT STARTED**

Ziel: das laufende Overlay nutzt für Tracking/Playspace den Core, ohne Verhaltensänderung.

Aufgaben:
1. Adapter `GdroidVRBackend` implementiert `IVRBackend` auf Basis von `VRXR_*`.
2. `gquest_vr`-Lua-Modul liest künftig aus dem Core statt direkt aus dem Snapshot,
   **API unverändert** (Addons dürfen nicht brechen).
3. A/B-Vergleich: Posen vor/nach Umbau müssen innerhalb 1e-3 übereinstimmen.

Akzeptanz: bestehende Lua-Harnesses grün **und** Quest-3-Lauf ohne sichtbare Änderung.
Regel: kein Merge ohne Hardware-Gegenprobe.

---

### Phase 6 — VR-Player, Hände, Interaktion im Core — **NOT STARTED**

Ziel: Grab/Throw/TwoHand als Core-Logik, host-unabhängig.

Aufgaben:
1. `HandState`, `GrabState`, `TwoHand`-Solver.
2. `WeightPolicy` mit Server-Hook (Client darf nur anfragen).
3. Finger-Curl-Quellen: Controller-Profil (Tabelle übernehmen) und Hand-Tracking.
4. Akzeptanztest aus dem Pistolen-Protokoll als Regressionsfall.

Akzeptanz: Zwei-Hand-Stabilität auf Quest 3 nicht schlechter als heute
(SMG-Zweihandgriff ist heute bestätigt — das ist die Messlatte).

---

### Phase 7 — Sandbox-Kern und 3D-Spawn-Menü — **NOT STARTED**

Aufgaben:
1. `ObjectModel`, `SandboxCommand`, `UndoStack`.
2. Serialisierung + Save/Load mit Prüfsumme und Recovery.
3. Spawn-Menü als Core-Zustand, Host rendert.

Akzeptanz: 100 Objekte spawnen, verschieben, einfrieren, löschen, Undo/Redo vollständig,
Save/Load byte-stabil (Round-Trip-Test).

---

### Phase 8 — Waffen und Tools — **PARTIALLY IMPLEMENTED (im Overlay)**

Heute vorhanden: 7 HL2-Waffenfamilien mit manuellem Nachladen, Griff-/Mündungskorrektur,
native Fingerprofile, Physgun. **Aber:** alles im Engine-Lua des Overlays, nichts im Core.

Aufgaben:
1. `WeaponState` im Core, Engine bleibt Wahrheit (kein erfundener Zustand).
2. Tool-System (Physgun, Toolgun) als Core-Tools mit Host-Constraint-Ausgabe.
3. Weitere Waffen einzeln verifizieren — je Waffe ein Eintrag wie das Pistolen-Protokoll.

Akzeptanz: pro Waffe eine protokollierte native Zustandsfolge (Magazin/Kammer/Reserve),
nicht nur eine Trägerbestätigung.

---

### Phase 9 — NPC und KI — **NOT STARTED**

Auf Host GDroid: Engine-NPCs nutzbar (HL2/GMod). Eigene KI nur für Host Native nötig.
Aufgaben: `NavigationAgent`, `Perception`, minimale Behavior-Trees.

Akzeptanz: 20 NPCs auf Quest 3 im Performance-Profil ohne Frametime-Einbruch über Budget.

---

### Phase 10 — Fahrzeuge — **NOT STARTED**

Auf Host GDroid: Engine-Fahrzeuge, VR-Einstieg über Core-Interaktion.
Aufgaben: Sitze, Attachment-basierte Augenpose (VRMod-Konzept), Lenkrad-Greifen.

Akzeptanz: Einsteigen, Fahren, Aussteigen auf Quest 3 bestätigt.

---

### Phase 11 — Multiplayer (Quest↔Quest) — **NOT STARTED**

Aufgaben:
1. `core/net` Protokoll v1: `pose`, `interact`, `sandbox`, `world`, `meta`.
2. Listen Server + Dedicated Server.
3. Interest Management (Zell-Grid), Rate-Limits, Server-Validierung.

Akzeptanz: zwei Quest-3-Geräte sehen Kopf, Hände und Finger des anderen;
Grab/Throw eines Props ist serverautoritativ und ohne Rubber-Banding spielbar.

---

### Phase 12 — Crossplay — **BLOCKED (architektonisch)**

**Befund:** GDroid existiert nur für Android. Ein PCVR-Host mit GDroid gibt es nicht.
Crossplay Quest↔PCVR ist damit **heute nicht umsetzbar**, unabhängig vom Aufwand.

Mögliche Wege, jeder mit eigenem Proof-Gate:

| Weg | Voraussetzung | Risiko |
|---|---|---|
| A: PC-Build derselben Source-Engine-Familie | Protokoll-Kompatibilität nachweisen | hoch — Protokolle sind nichtöffentlich/versionsgebunden |
| B: Host Native auf beiden Seiten | Host Native muss existieren (Phase 21+) | sehr hoch — Jahre |
| C: Kein Crossplay, nur Quest↔Quest | – | kein Erfüllungsgrad für Master-Prompt |

Empfehlung: Crossplay in der Roadmap **hinter** Phase 21 (PCVR-Host) legen und
bis dahin ausdrücklich als nicht verfügbar dokumentieren. Keine Ankündigung ohne
Test zwischen zwei echten Geräten.

---

### Phase 13–16 — Lua, Modding, Mod-Manager, Workshop-Backend — **NOT STARTED**

Aufgaben: Sandbox-VM, Permission-Modell, API-Versionierung, Addon-Manifest,
Dependency-Graph, Konfliktprüfung, Plattformfilter, lokales Addon-System,
Backend-**Abstraktion** (kein Fake-Cloud). Ein echter Workshop braucht ein echtes Backend.

Akzeptanz: ein Addon mit `sandbox.spawn` spawnt Objekte; ein Addon ohne Permission kann
es nicht; ein Addon mit Endlosschleife wird nach Budget beendet, ohne den Server zu töten.

---

### Phase 17–18 — Maps und Map-Editor — **NOT STARTED**

Erst Map-Browser/Loader/Validierung, dann Editor. Auf Host GDroid sind BSP-Maps
engine-seitig vorhanden — der Core braucht nur Metadaten + Spawnpunkte.

---

### Phase 19–23 — Audio, Spatial UI, Optimierung, Security, QA — **NOT STARTED**

Reihenfolge wie im Master-Prompt, aber mit einer Änderung: **Quest-Performance wird ab
Phase 6 mitgemessen**, nicht erst in Phase 20. Ein Vertical Slice, der erst am Ende
profiliert wird, ist kein Vertical Slice.

---

### Phase 24 — Release-Builds — **NOT STARTED**

Debug / Development / Release APK, reproduzierbar, mit dokumentierten Hashes.
PCVR-Builds erst nach Phase 21.

---

## 4. Quest 3 / Quest 3S

| Punkt | Quest 3 | Quest 3S |
|---|---|---|
| Status | PARTIALLY IMPLEMENTED, hardwarebestätigt | **NOT TESTED** |
| Eye-Resolution-Stufe | 1680×1760 (Schärfer) | 1374×1440 (Ausgewogen) |
| Default-Profil | Schärfer, 90 Hz | Ausgewogen, 72 Hz |
| Geräteerkennung | liest `Build.MODEL` | liest `Build.MODEL` |
| Bekannte offene Punkte | Frametime-Messung fehlt systematisch | kompletter Ersteindruck fehlt |

**Quest-3S-Anpassungen, die sicher nötig sind:**
1. ~~Eigenes Default-Profil~~ — **erledigt**: eigene Stufen 916×960 / 1374×1440 /
   1558×1632, Empfehlung Ausgewogen bei 72 Hz, im Menü je Gerät gemerkt. Offen bleibt
der Hardware-Nachweis auf einem 3S.
2. Höhenkalibrierung erneut prüfen (anderes Gehäuse, anderes Sichtfeld).
3. Controller-Offset-Profile getrennt halten (nicht hartkodiert auf ein Gerät).
4. Frametime-Budget: 72 Hz ⇒ 13,9 ms; Ziel ≤ 12 ms für Reserve.

**Blocker:** kein Gerät in dieser Umgebung. Muss vom Nutzer auf Hardware geprüft werden.

---

## 5. PCVR

| Punkt | Status |
|---|---|
| Host Native | NOT STARTED |
| OpenXR direkt (ohne libvrxr) | NOT STARTED |
| Eigener Renderer | NOT STARTED |
| SteamVR-Kompatibilität | NOT STARTED |
| Quest Link / Air Link | NOT STARTED |

Realistische Reihenfolge: erst Core-Tests gegen einen **Fake-Host** (Phase 4), dann
ein minimaler OpenXR-Host, der **nur** Kopf + Hände + ein Testobjekt darstellt
(„VR Hello World“), dann Physik, dann Inhalte. Kein PCVR-Erfolg wird behauptet, bevor
ein Frame auf einem echten Headset erschienen ist.

---

## 6. Kritische Entscheidungen, die der Nutzer bestätigen muss

Diese Entscheidungen ändern den Projektcharakter und sind nicht rückholbar ohne
Substanzverlust. Ich treffe sie nicht allein:

**E1 — Grundstrategie.** ~~Geteilter Core mit zwei Hosts, nur Overlay oder nur Neubau?~~
**Entschieden am 15. November 2026: geteilter Core, zwei Hosts** — der zweite Host erst
nach den Gates G1–G4 in `PROJECT_STATUS.md` §12, mit Abbruchkriterien. Nur Overlay wäre der
Ist-Zustand (bricht mit jedem GDroid-Update), Nur-Neubau hätte keinen belegten Pfad zu
Renderer, Physik und Netcode.

**E2 — Inhalte.** GQuest V2 bleibt auf Retail-GMod-Inhalte angewiesen. Soll ein eigenes
Asset-Paket (eigene Maps, Props, Waffenmodelle) parallel entstehen, damit das Spiel
irgendwann ohne Fremdinhalte installierbar ist?

**E3 — Lizenz.** ~~Der eigene Code hat keine Lizenz.~~ **Erledigt:** MIT für den eigenen
Code (`LICENSE`), Herkunftsaufstellung und zlib-Kennzeichnungspflicht in
`THIRD_PARTY_NOTICES.md`, zlib-Volltext in `third_party/VRMod-zlib-LICENSE.txt`.
Damit ist die Übernahme von VRMod-Code rechtlich vorbereitet — die Kopfkommentar-Vorlage
und die Eintragstabelle stehen bereit, ausgelöst wird sie erst bei tatsächlicher Übernahme.

**E4 — GDroid-Abhängigkeit.** Bleibt GDroid 0.1.30 dauerhaft die Basis (eingefroren),
oder wird aktiv mit neuen GDroid-Versionen mitgezogen (jede = neue Offset-Jagd)?

---

## 7. Reihenfolge für „Mach weiter“

1. `PROJECT_STATUS.md` lesen.
2. `git status` prüfen.
3. Die erste Aufgabe mit Status **IN DEVELOPMENT** oder **NOT STARTED** nehmen,
   deren Blocker nicht offen ist.
4. Echten Code schreiben, Core-Tests ausführen, Ergebnis dokumentieren.
5. `PROJECT_STATUS.md` und Roadmap aktualisieren, committen.

Nächste konkrete Aufgabe nach diesem Plan: **Phase 3** (Build-Reproduzierbarkeit),
weil ohne lauffähige Core-Tests jede weitere Phase nicht prüfbar ist.
