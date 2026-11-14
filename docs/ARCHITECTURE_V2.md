# GQuest V2 — Zielarchitektur

Stand: 14. November 2026
Status: **Architekturentwurf.** Kein Code dieser Architektur existiert bereits,
außer den in `docs/SOURCE_ANALYSIS.md` als „wiederverwendbar“ markierten Teilen.

---

## 1. Ausgangslage und die zentrale Entscheidung

Der Master-Prompt verlangt ein eigenständiges VR-Sandbox-Spiel mit Quest 3/3S, PCVR,
Crossplay, Lua-Modding und eigenem Netcode. Die Analyse hat drei harte Randbedingungen
ergeben:

1. **GDroid ist geschlossen.** Kein Refactoring möglich, nur Binary-Overlay.
2. **GDroid existiert nur für Android.** Kein PC-Build → kein Crossplay mit GDroid.
3. **VRMods VR-Backend ist geschlossen.** Nur die Lua-Ebene ist adaptierbar.

Daraus folgen genau zwei realistische Wege:

| Weg | Was es ist | Zeit bis spielbar | Risiko |
|---|---|---|---|
| **A: Overlay** | GQuest bleibt gepatchtes GDroid-Overlay | Wochen | bricht bei jedem GDroid-Update |
| **B: Eigene Runtime** | eigener Renderer + Physik + Netcode | Jahre | Größe des Projekts |

**Empfehlung: Weg C — geteilter Core, zwei Hosts.** Nicht weil es elegant klingt,
sondern weil es der einzige Weg ist, bei dem heute etwas läuft **und** langfristig
Eigenständigkeit entsteht.

```
                    ┌──────────────────────────┐
                    │      GQUEST CORE         │  engine-agnostisches C++20
                    │  (keine Engine-Header)   │
                    └────────────┬─────────────┘
                                 │  IPlatformHost / IVRBackend / IAssetSource
                 ┌───────────────┴────────────────┐
                 │                                │
        ┌────────▼────────┐              ┌────────▼─────────┐
        │  HOST GDROID    │              │  HOST NATIVE     │
        │  Android/ARM64  │              │  Windows/Linux   │
        │  OpenXR via     │              │  OpenXR direkt   │
        │  libvrxr.so     │              │  + eigener       │
        │  Source-Engine  │              │    Renderer      │
        └────────┬────────┘              └────────┬─────────┘
                 │                                │
        ┌────────▼────────┐              ┌────────▼─────────┐
        │ Quest 3 / 3S    │              │ PCVR             │
        └─────────────────┘              └──────────────────┘
```

Der Core kennt **keine** Engine. Er kennt Posen, Interaktionen, Objektzustand,
Netzwerkregeln und Lua. Der Host liefert Rendering, Physik-Solver und Asset-Zugriff.

**Crossplay-Regel, die daraus folgt:** Crossplay ist nur zwischen Hosts möglich, die
denselben Core **und** dieselbe Objekt-/Netzwerkversion sprechen. Quest↔Quest (Host
GDroid) ist erreichbar. Quest↔PCVR ist **erst** erreichbar, wenn der PCVR-Host
denselben Core spricht — das heißt: nicht mit GDroid-Inhalten, sondern mit
Host-Native-Inhalten oder über einen gemeinsamen Source-Engine-PC-Build. Das ist in
`MIGRATION_PLAN.md` als Phase 12 mit explizitem Proof-Gate festgehalten.

---

## 2. Core-Module

Der Core ist eine statische Bibliothek ohne Engine-Abhängigkeiten, Ziel: < 15k Zeilen.

```
core/
├── platform/      IPlatformHost, IVRBackend, IAssetSource, IClock, ILog
├── math/          Vec3, Quat, Transform, Interpolation (SLERP, Hermite)
├── vr/
│   ├── tracking     PoseSnapshot, TrackingState, Validitäts-Gates
│   ├── input        ActionSet, ActionBinding, Edge-Erkennung, Left-Handed
│   ├── playspace    Origin/OriginAngle, Recenter, Height/Reach-Kalibrierung
│   ├── comfort      Vignette, Snap/Smooth-Turn, Teleport-Ziele
│   └── hands        HandState, FingerCurl[15], Grip-Konfidenz
├── interaction/   Grab, Throw, TwoHand, Trigger-Zonen, Interactable
├── physics/       ConstraintRequest, GrabSpring, Masse/Gewicht-Policy
├── sandbox/       ObjectModel, SpawnRequest, UndoStack, Snapshot-Format
├── weapons/       WeaponDef, Magazine, Chamber, ActionState, Attachment
├── tools/         ToolDef, ConstraintTool, WeldTool, PhysgunPolicy
├── ai/            NavigationAgent, Perception, BehaviorTree (minimal)
├── net/
│   ├── protocol     Nachrichten, Versionierung, Bitarithmetik
│   ├── authority    Server-Validierung, Rate-Limits
│   ├── relevance    Interest Management, Zell-Grid
│   └── predict      Client-Prediction, Reconciliation, Interpolation
├── lua/           Sandbox-VM, Permission-Modell, API-Registry, Limits
├── modding/       Addon-Manifest, Dependency-Graph, Konfliktprüfung
├── save/          Versioniertes Format, Checksummen, Recovery
└── audio/         Spatial-Source-Interface (Host implementiert)
```

### 2.1 Warum diese Schnitte

Jeder Schnitt entspricht einer Bruchlinie, die im alten GQuest oder in VRMod
nachweislich weh tut:

- **`vr/playspace` getrennt von `vr/input`:** VRMod vermischt Snap-Turn (`Think`) und
  Smooth-Turn (`PreRender`). Getrennt nach Simulations-Tick und Render-Frame ist es
  testbar und dediziert-serverfähig.
- **`interaction` getrennt von `physics`:** Der Core entscheidet *was* gegriffen wird,
  der Host *wie* es simuliert wird. Damit funktioniert derselbe Grab-Code auf der
  Source-Physik und auf Jolt.
- **`net/` im Core, nicht im Host:** Sonst kann Host GDroid nie mit Host Native reden.
- **`lua/` im Core:** Die Engine-Lua ist nicht sandboxed. Eine eigene VM mit
  Permission-Modell ist Voraussetzung für Mods von fremden Autoren.

---

## 3. Plattform-Abstraktion

Vier Interfaces, bewusst klein gehalten:

```cpp
struct IPlatformHost {
    virtual ~IPlatformHost() = default;
    virtual IClock&          clock()      = 0;
    virtual ILog&            log()        = 0;
    virtual IAssetSource&    assets()     = 0;
    // Physik: Core fragt an, Host simuliert.
    virtual PhysicsHandle    create_body(const BodyDesc&) = 0;
    virtual void             apply_impulse(PhysicsHandle, const Vec3&) = 0;
    virtual Transform        body_transform(PhysicsHandle) const = 0;
    virtual TraceResult      trace(const TraceDesc&) const = 0;
    // Darstellung: Core beschreibt, Host zeichnet.
    virtual RenderHandle     create_instance(const RenderDesc&) = 0;
    virtual void             set_instance_transform(RenderHandle, const Transform&) = 0;
    virtual void             destroy_instance(RenderHandle) = 0;
};

struct IVRBackend {
    virtual ~IVRBackend() = default;
    virtual bool             poll(PoseSnapshot&) = 0;   // genau ein Snapshot pro Frame
    virtual bool             action_state(const ActionRef&, Hand, float& x, float& y) = 0;
    virtual bool             action_edge(const ActionRef&, Hand, bool& down) = 0;
    virtual void             haptic(Hand, float seconds, float hz, float amplitude) = 0;
    virtual DisplayInfo      display() const = 0;       // Auflösung, FOV, Rate
    virtual void             recenter() = 0;
};
```

Regeln, die im Code erzwungen werden (nicht nur dokumentiert):

1. **Der Core öffnet niemals eine OpenXR-Session.** Nur der Host besitzt die Session.
   (Das alte GQuest macht das bereits richtig — Kommentar in `lib.rs`: „starts no second
   OpenXR session“. Diese Regel wird beibehalten.)
2. **Der Core ruft keine Engine-Symbole.** Kein `#include` aus `tier0`, `vphysics`,
   `engine`. Ein CI-Check verbietet diese Header im `core/`-Baum.
3. **Quest-spezifischer Code lebt nur in `host_gdroid/`**, PCVR-Code nur in
   `host_native/`. Gemeinsam ist ausschließlich `core/`.

---

## 4. VR-System

### 4.1 Tracking-Modell

Ein `PoseSnapshot` pro Frame, unveränderlich, mit expliziter Gültigkeit:

```
struct PoseSnapshot {
    uint64_t frame;          // monoton
    double   predicted_time; // XR-Zeitpunkt
    Pose     head;
    Pose     hand[2];
    Pose     aim[2];
    float    finger_curl[2][15];
    uint32_t valid_mask;     // Bit je Pose + Bit je Finger
};
```

Harte Regeln aus den Erfahrungen des alten GQuest:

- Jede Pose trägt ein Gültigkeitsbit. Ungültig ⇒ **nicht** verwenden, nicht auf
  Null-Pose zurückfallen und diese als echt ausgeben.
- Alle Floats werden auf `isfinite` geprüft (der C++-Test `vr_lua.cpp` deckt das ab).
- Quaternion-Norm wird auf `0.5 … 1.5` geprüft, bevor Euler-Winkel berechnet werden.
- Veraltete Snapshots (Alter > 2 Frames) markieren `valid_mask = 0` für Hände.
- 3-Punkt (HMD + 2 Controller) und 6-Punkt (zusätzlich Waist + 2 Füße) sind getrennte
  Fähigkeitsflags, keine Annahmen.

### 4.2 Playspace

```
origin       : Weltposition des Playspace-Ursprungs
origin_angle : yaw-only Rotation
```

Snap-Turn und Smooth-Turn rotieren **nur** `origin` um die Spielerposition, nie die
Kamera. Das ist VRMods Ansatz und er ist korrekt. Der Unterschied: Turn-Input wird pro
**Simulations-Tick** konsumiert, die resultierende Rotation pro Frame interpoliert.
Seated/Standing unterscheiden sich nur in der Initialisierung von `origin.z` und in der
Kalibrierung, nicht im Tracking-Code.

### 4.3 Hände

`HandState` ist Core-Eigentum, nicht Modell-Eigentum:

```
struct HandState {
    Pose    pose;
    Pose    aim;
    float   curl[15];
    Hand    primary;        // Left-Handed-Mode
    GrabState grab;         // None | Aiming | Holding | TwoHand
};
```

Finger-Curls kommen aus zwei Quellen: echtem Hand-Tracking (falls verfügbar) oder aus
Controller-Profiltabellen (das alte GQuest hat dafür bereits 12 Profile mit exakt
15×3 Floats pro Zustand — diese Tabelle wird unverändert übernommen).

### 4.4 Komfort

Jede Komfortfunktion ist abschaltbar und einzeln konfigurierbar:
Smooth Locomotion, Snap-Turn (Winkel 30/45/60), Smooth-Turn-Rate, Teleport,
Dash, Vignette (Intensität), Sitzmodus, Stehmodus, Höhen-/Reichweiten-Kalibrierung,
Recenter, Linkshänder-Modus.

**Regel:** Keine Komforteinstellung darf Gameplay-Vorteile geben. Teleport und
Smooth-Motion müssen dieselbe Distanz in derselben Zeit erlauben.

---

## 5. Physik

Der Core beschreibt, der Host simuliert. Der Core kennt nur:

- `GrabSpring`: Zielpose, Steifigkeit, Dämpfung, Max-Kraft
- `WeightPolicy`: maximale Masse pro Hand, Zwei-Hand-Verstärkung
- `ConstraintRequest`: Weld, Rope, Hinge, Motor, Piston, Axis
- `ThrowState`: Geschwindigkeitsableitung aus Handbewegung über N Frames

Server-autoritativ heißt: der Server hält die Constraint-Liste, der Client hält nur
eine Vorschau. Der Server lehnt Constraint-Erzeugung ab, wenn Masse/Größe/Limit
überschritten sind (VRMods `vrmod_pickup_weight`-Prinzip, auf Constraints erweitert).

---

## 6. Sandbox

### 6.1 Objektmodell

```
ObjectId (uint64, serververgeben, monoton)
ObjectKind: Prop | Entity | NPC | Weapon | Vehicle | Tool | Ragdoll | Constraint
ObjectState: transform, velocity, frozen, owner, group, scale, links[]
```

Alle Mutationen laufen über `SandboxCommand` — ein serialisierbares Objekt. Damit sind
Undo/Redo, Netzwerk-Replikation und Save/Load **ein** Mechanismus, nicht drei.

```
Spawn, Delete, Transform, Freeze, Scale, Duplicate, Link, Unlink, Group
```

Undo ist ein Stapel von Command-Inversen. Redo ist derselbe Stapel rückwärts.
Multi-Select ist eine `ObjectId`-Menge, keine Sonderbehandlung.

### 6.2 Spawn-Menü (3D)

Zustand: Kategorie, Suchtext, Filter, Auswahl, Vorschau-Handle.
Die Vorschau ist ein Core-`RenderHandle` im Host — keine zweite Welt.

Jeder Eintrag kommt aus dem Addon-Manifest mit den Feldern
`name, description, author, addon, size, dependencies, quest, pcvr, crossplay`.
Die drei Kompatibilitätsfelder steuern, ob ein Eintrag auf dem aktuellen Host
ausgegraut wird — **nicht** ob er versteckt wird (Nutzer sollen sehen, warum).

---

## 7. Waffen und Werkzeuge

### 7.1 Waffenzustand (Core-Eigentum)

```
struct WeaponState {
    WeaponId          def;
    int               rounds_in_mag;
    int               mag_capacity;
    int               chambered;
    MagazineSlot      attached;
    ActionState       action;      // Idle | Ejecting | Inserting | Racking | Firing
    FireMode          mode;
    SafetyState       safety;
    AttachmentSet     attachments;
};
```

**Grundsatz aus dem alten GQuest, der zwingend bleibt:** Der Core erfindet **keinen**
Munitionszustand. Ein Nachladen ist eine Zustandsfolge, die vom Host (Engine) bestätigt
wird. Wenn der Host keinen verlinkten Magazin-Container meldet, ist die Antwort
„noch nicht bereit“ — nicht „Magazin voll“.

Die Protokolle in `docs/Gquest-HL2-reload-verification.json` zeigen genau diese
Sequenz für die Pistole (Magazin 18 → auswerfen → Reserve 184 → 166 → neues Magazin
18 → durchladen → Kammer 1 → Schüsse 17/16/15/14/13). Diese Sequenz ist der
Akzeptanztest für jede künftige Waffe.

### 7.2 Werkzeuge

`ToolDef` = Name, Handmodell, Ziel-Trace, Aktion, Constraint-Ausgabe.
Physgun und Toolgun sind **Tools**, keine Sonderfälle im Kern. Der Modder-API-Zugang
ist derselbe wie für eingebaute Tools.

---

## 8. Netzwerk

### 8.1 Rollen

| Rolle | Autorität | Einsatz |
|---|---|---|
| Dedicated Server | voll | öffentliche Server, kein Rendering |
| Listen Server | voll + lokal rendern | Koop, kleine Gruppen |
| Client | keine | Vorhersage + Interpolation |

### 8.2 Kanäle

| Kanal | Rate | Inhalt |
|---|---|---|
| `pose` | 30–72 Hz | Kopf, Hände, Finger (bit-gepackt) |
| `interact` | ereignisbasiert, rate-limited | Grab, Release, Use, Reload-Schritt |
| `sandbox` | ereignisbasiert | Commands (spawn/delete/transform) |
| `world` | Snapshot 10–20 Hz | Objektzustand, Constraints, NPCs |
| `meta` | selten | Lobby, Konfiguration, Mod-Liste |

Bit-Packing für Posen (VRMod-Vorbild: 7 Bit pro Finger, 7 Bit yaw) wird übernommen,
aber mit Zeitstempel pro Frame und Delta-Kompression gegen den letzten bestätigten
Frame. `SteamID` wird **nicht** als Key verwendet — der Core nutzt eine eigene
`PlayerId`, die der Host vergibt (löst VRMods Portabilitätsproblem).

### 8.3 Interest Management

Zell-Grid über die Welt, Zellgröße konfigurierbar. Ein Client erhält:
alle Objekte in seiner Zelle + Nachbarzellen + alles, was er selbst besitzt oder hält.
Posen anderer Spieler nur innerhalb der Sichtdistanz, dann auf 10 Hz reduziert.
Das ersetzt VRMods „alles an alle“.

### 8.4 Vorhersage

Nur lokal vorhergesagt werden: eigene Bewegung, eigener Waffenzustand, eigene
Grab-Pose. Alles andere ist Serverzustand. Reconciliation über `command_seq` +
Server-Snapshot; bei Abweichung > Toleranz wird die lokale Pose korrigiert und die
Differenz visuell geglättet.

---

## 9. Lua und Modding

### 9.1 Sandbox

- Eigene Lua-5.4-VM pro Addon (nicht die Engine-VM).
- Kein `os`, `io`, `package`, `debug`, kein `load`/`loadstring` aus Strings.
- Budget pro Addon: Instruktionszähler, Speicherlimit, Wall-Clock-Limit pro Tick.
- Fehler werden pro Addon isoliert: ein Addon-Crash deaktiviert nur dieses Addon.
- API-Zugriff nur über registrierte, versionierte Namespaces.

### 9.2 Permission-Modell

```
addon.json:
{
  "id": "...", "version": "...", "api": 2,
  "permissions": ["sandbox.spawn", "net.server", "ui.panel"],
  "platforms": ["quest", "pcvr"],
  "dependencies": [{"id": "...", "range": ">=1.2 <2"}]
}
```

Permissions sind positiv gelistet; alles andere ist verboten. `net.server` erlaubt
serverseitige Handler, `net.client` nur Client-Handler. Ein Addon ohne `sandbox.write`
kann keine Objekte erzeugen.

### 9.3 API-Versionierung

`api` ist eine Ganzzahl. Der Core hält N und N-1 gleichzeitig vor. Breaking Changes
erhöhen `api`. Ein Addon mit unbekannter `api` wird deaktiviert, nicht „best effort“
ausgeführt.

### 9.4 GMod-Kompatibilität

Es wird **keine** vollständige GMod-Kompatibilität behauptet. Eine
Kompatibilitätsschicht ist nur sinnvoll, wenn Host GDroid läuft — dort ist die
Engine-Lua ohnehin vorhanden und GMod-Addons funktionieren nativ. Für Host Native
wäre eine GMod-API-Emulation ein eigenes Großprojekt und ist **nicht** eingeplant.

---

## 10. Quest-Performance

Quest 3 und Quest 3S haben unterschiedliche native Panels (2064×2208 bzw. 1832×1920
pro Auge). Deshalb hat **jedes Gerät eigene Stufen**; dieselbe Zahl bedeutet auf dem
anderen Gerät eine andere Last.

| Gerät | Stufe | Eye-Resolution | Anteil nativ | Empfehlung |
|---|---|---|---|---|
| Quest 3 | Leistung | 1032×1104 | 50 % | – |
| Quest 3 | Ausgewogen | 1548×1656 | 75 % | – |
| Quest 3 | Schärfer | 1680×1760 | ~81 % | **Standard** (FFR 2, 90 Hz) |
| Quest 3S | Leistung | 916×960 | 50 % | – |
| Quest 3S | Ausgewogen | 1374×1440 | 75 % | **Standard** (FFR 2, 72 Hz) |
| Quest 3S | Schärfer | 1558×1632 | 85 % | – |

Die sechs Stufen sind die Allowlist des Rust-Profilparsers; jede andere Zeichenkette
fällt auf 1032×1104 zurück. Das VR-Menü wählt das Gerät und merkt sich pro Gerät die
letzte Wahl. FFR-Stufen 0–3 und Raten 72/90 Hz gelten für beide Geräte gleich.

### Geräteerkennung

Die Bridge liest beim Start `android.os.Build.MODEL` (Rückfall: `Build.DEVICE` mit den
Codenamen `panther`/`eureka`/`hollywood`/`seacliff`) und bildet daraus eine Geräte-ID
(`quest3`, `quest3s`, …). Das Modell gewinnt gegen den Codenamen; „Quest 3S“ wird vor
„Quest 3“ geprüft, weil es dessen Präfix ist.

Die ID geht über die Umgebungsvariable `GQUEST_DEVICE` an die Rust-Startkomponente und
zusätzlich als `data/gquest_device.txt` an das Lua-Menü, damit beide dieselbe Annahme
haben. Die Erkennung läuft vor dem Laden des Profils und vor dem ersten XR-Swapchain,
weil die Eye-Resolution beim Start festgeschrieben wird.

| Lage | Ergebnis |
|---|---|
| keine Profildatei | Empfehlung des erkannten Geräts |
| Stufe nicht im Satz des erkannten Geräts | Empfehlung statt fremder Auflösung |
| Stufe gültig, gleiches Gerät | gespeicherte Wahl bleibt |
| Gerät unbekannt oder `Build` nicht lesbar | gespeicherte Wahl bleibt |

Die Stufensätze beider Geräte sind disjunkt, deshalb genügt die Gültigkeitsprüfung; die
Gerätezeile der Datei liest nur das Menü.

Im VR-Menü steht direkt unter der Geräteauswahl eine Statuszeile mit drei Zuständen:
`Erkannt: <Gerät> - passt zur Auswahl` (grün), `Erkannt: <Gerät> - Auswahl weicht ab`
(orange) und `Erkannt: kein Geraet - Auswahl manuell` (grau). Damit ist eine
fehlgeschlagene Erkennung sichtbar, statt sich nur als unerwartete Bildrate zu zeigen.

Die Texte bleiben unter `P.STATUS_LINE_BUDGET` = 60 Zeichen (heute maximal 38), was auf
eine Zeile bei 580 px Labelbreite ausgelegt ist. Das Budget ist aus der Schriftgröße
abgeleitet, nicht in Derma gemessen. Der Zeilenhöhe wird zusätzlich aus der Textlänge
berechnet und das Label bekommt `SetAutoStretchVertical(true)`, damit ein längerer
Gerätename umbricht statt abgeschnitten zu werden.

**Nicht geprüft:** das tatsächliche Derma-Rendering. Hier läuft kein GMod, also sind
Umbruchpunkt, Farben und Zeilenhöhe im Headset unbestätigt.

**Nicht getestet:** das Lesen der Java-Felder selbst (braucht Android). Getestet ist die
Klassifizierung (`tests/device_model.cpp`) und die Auflösungslogik (Rust- und
Lua-Harness).

PCVR nutzt dieselben Mechanismen mit eigener Skalierung („Quality+“).

Techniken, die im Core verankert werden (nicht dem Host überlassen):
LOD-Stufen pro Objekt, Distanz-Culling, Instancing-Gruppierung, Occlusion-Abfragen als
Host-Callback, asynchrones Asset-Laden mit Priorität nach Sichtbarkeit,
dynamische Auflösung als Host-Feature mit Core-Rückmeldung (Frame-Time-Budget).

---

## 11. Save-System

Ein Format, drei Verwendungen: Sandbox-Save, Server-Snapshot, Mod-Profil.

```
header: magic, format_version, core_version, addon_set_hash
body:   object list, constraint list, player state, world state
footer: sha256, count check
```

Recovery: Header lesen → Version prüfen → Body parsen → Footer prüfen. Bei Fehler wird
die vorherige Sicherung geladen und der Fehler geloggt. Kein stiller Teil-Load.

---

## 12. Sicherheit

| Ebene | Maßnahme |
|---|---|
| Netzwerk | Server validiert jede Command; Client sendet Absichten, keine Ergebnisse |
| Rate-Limits | pro Kanal und pro Spieler, Verstoß ⇒ Drop + Log |
| Lua | Sandbox, Permission-Liste, Budgets, Fehlerisolierung |
| Administration | Kick, Ban, Rollen, Audit-Log |
| Mods | Manifest-Signatur optional, Konfliktprüfung, Plattformfilter |
| Native | bestehende Signaturprüfung + Fail-Closed der Bridge bleibt Pflicht |

Das Sicherheitsniveau der bestehenden Bridge (Byte-Signatur vor Patch, `mprotect`
zurück auf Originalrechte, `MAP_FIXED_NOREPLACE`, Trampolin-Reichweitenprüfung) ist
Vorbild für alle künftigen nativen Eingriffe.

---

## 13. Build-System

Ziel: **ein** Befehl pro Ziel, klare Fehlermeldung pro fehlender Abhängigkeit.

```
./gq build core            # Core + Unit-Tests (keine Engine nötig)
./gq test core             # läuft in CI
./gq build host-native     # PCVR (Windows/Linux)
./gq build host-gdroid     # Android-Overlay (braucht private Basis)
./gq package quest         # Debug/Dev/Release APK
```

Jede fehlende Voraussetzung erzeugt eine Meldung mit Pfad, Zweck und Beschaffungshinweis
— nicht einen Python-Traceback. Der frühere `rtk proxy`-Wrapper ist bereits entfallen,
und `build.py --check` / `--tests` setzen diesen Punkt um.

---

## 14. Architekturentscheidungen (ADR-Kurzform)

| # | Entscheidung | Alternative | Grund |
|---|---|---|---|
| ADR-1 | Geteilter Core + zwei Hosts | nur Overlay / nur Neubau | einziger Weg zu heute lauffähig **und** langfristig eigenständig |
| ADR-2 | GDroid bleibt Binary, wird nicht geforkt | Neubau der Engine | Quelle nicht verfügbar |
| ADR-3 | Eine OpenXR-Session, Owner = Host | Core öffnet Session | doppelte Session crasht |
| ADR-4 | Core engine-frei, CI-erzwungen | Engine-Typen im Core | sonst kein zweiter Host möglich |
| ADR-5 | VRMod nur als Konzeptquelle + zlib-konforme Adaption | Code 1:1 kopieren | Lizenzpflicht + Modul fehlt |
| ADR-6 | Eigene `PlayerId` statt SteamID | SteamID als Key | Crossplay-Portabilität |
| ADR-7 | SandboxCommand als einziger Mutationsweg | direkte Objektmanipulation | Undo/Netz/Save in einem Mechanismus |
| ADR-8 | Munitionszustand nie erfunden | Client-seitig auffüllen | verifizierte Engine-Semantik (Pistolen-Protokoll) |
| ADR-9 | Server-autoritative Constraints | Client-Physik vertrauen | sonst Exploit im Multiplayer |
| ADR-10 | Crossplay erst nach Protokoll-Proof | „geht schon“ annehmen | GDroid hat keinen PC-Build |

---

## 15. Was diese Architektur ausdrücklich **nicht** löst

- Sie macht GDroid nicht quelloffen.
- Sie ersetzt keine Retail-Inhalte.
- Sie liefert keinen PCVR-Build in Phase 1.
- Sie behauptet keine GMod-Addon-Kompatibilität außerhalb von Host GDroid.
- Sie reduziert den Umfang des Gesamtprojekts nicht — sie ordnet ihn nur so, dass
  jeder Schritt einzeln prüfbar bleibt.
