# Herkunft und Lizenzen

Dieses Dokument ist die verbindliche Lizenzübersicht für das Repository. Es trennt
drei Dinge, die oft vermischt werden:

1. **Eigener Code** — wem gehört er, unter welcher Lizenz steht er.
2. **Externe Abhängigkeiten** — was wird benutzt, aber nicht weitergegeben.
3. **Fremde Inhalte** — was darf aus rechtlichen Gründen gar nicht im Repository liegen.

Stand: 14. November 2026

---

## 1. Eigener Code

Alle eigenen Quellen in diesem Repository — C++-Bridge, Rust-Startkomponente, GLua-Modul,
Lua-Overlay, Python-Build- und Prüfwerkzeuge, Tests und Dokumentation — stehen unter der
**MIT-Lizenz**, siehe [LICENSE](LICENSE).

```
Copyright (c) 2026 shiftmann
```

Das umfasst ausdrücklich **nicht**:

- die GDroid-APK oder Teile davon,
- Garry's-Mod-, HL2- oder andere Valve-/Facepunch-Inhalte,
- VRMod-Code oder -Assets,
- Modell-, Textur- und Sounddateien Dritter.

Für diese gilt Abschnitt 2 bis 4.

---

## 2. Laufzeitbasis: GDroid

| Feld | Wert |
|---|---|
| Projekt | GDroid — <https://github.com/tinsarfal/GDroid> |
| Genutzte Version | 0.1.30, Paket `com.gmodvr.qvrx` |
| Art der Nutzung | **Binary-Abhängigkeit.** Die APK wird beim Build lokal vorausgesetzt, gepatcht und neu signiert. |
| Quellcode | **nicht veröffentlicht.** Das Upstream-Repository enthält ausschließlich eine README. |
| Lizenz | keine Lizenz im Repository; es werden keine Rechte eingeräumt |
| Weitergabe | **Diese APK wird nicht in diesem Repository weitergegeben.** |

Konsequenz: GQuest ist kein Fork von GDroid und kann keinen GDroid-Quellcode
„übernehmen“. Es ist ein Overlay auf einer separat beschafften Fremd-APK.

Laut GDroid-README basiert die Engine auf **nillerusr's Android-Source**-Arbeit; die
Touch-Steuerung stammt von **IzuIzu**. Beide werden hier als Herkunftsangabe genannt,
ohne dass Rechte an ihrem Werk beansprucht werden.

---

## 3. VR-Referenz: VRMod / gVRMod — zlib, mit Kennzeichnungspflicht

| Feld | Wert |
|---|---|
| Projekte | <https://github.com/Metastruct/vrmod> (VRMod x64 Extended), im Projekt genannt: <https://github.com/Abyss-c0re/gVRMod> |
| Original | Copyright (c) 2019 **Catse** |
| Veränderte Version | Copyright (c) 2025 **Abyss-c0re** |
| Lizenz | zlib-Style, Volltext in [third_party/VRMod-zlib-LICENSE.txt](third_party/VRMod-zlib-LICENSE.txt) |
| Umfang im Upstream | 76 Dateien, 15.971 Zeilen Lua + Assets |
| Nicht im Upstream enthalten | das native VR-Modul (`gmcl_vrmod_win64.dll` / `gmcl_vrmod_linux64.dll`) |

Die zlib-Lizenz erlaubt Nutzung, Veränderung und Weitergabe **auch kommerziell**, unter
drei Bedingungen:

1. Die Herkunft darf nicht falsch dargestellt werden; es darf nicht behauptet werden,
   man hätte das Original geschrieben.
2. **Veränderte Versionen müssen deutlich als verändert gekennzeichnet sein** und dürfen
   nicht als das Original dargestellt werden.
3. Der Lizenztext darf nicht entfernt oder verändert werden.

### 3.1 Aktueller Status: keine Kopie vorhanden

Eine Prüfung des Repositorys (Suche nach `catse`, `abyss`, `vrmod_`, `g_VR`, `VRUtil`,
`VRMOD_`, `NetReceiveLimited`, `ComputeShadowControl` in allen Lua-, C++-, Rust- und
Python-Quellen) ergibt: **es ist derzeit kein VRMod-Quellcode in dieses Repository
kopiert.** Übernommen wurden bisher ausschließlich **Konzepte** (Playspace-Modell,
Action-Manifest, serverseitige Pickup-Autorität, Physik-Hände). Konzepte sind keine
schutzfähige Übernahme; die Nennung erfolgt trotzdem, weil sie die Arbeit anderer sind.

### 3.2 Ausnahme: API-Interop in `gquest_weapon_align.lua`

Diese eigene Datei greift zur Laufzeit auf VRMod-Strukturen zu:

- liest und schreibt `g_VR.viewModelInfo`,
- hängt sich an den Hook `VRMod_Start`,
- spiegelt Werte über VRMods eigene API in dessen Waffenkonfiguration.

Das ist **Interop gegen eine öffentliche Laufzeit-API**, keine Ableitung von
VRMod-Code. VRMod selbst wird dabei weder verändert noch weitergegeben. Wird GQuest
zusammen mit VRMod betrieben, gilt für VRMod weiterhin dessen zlib-Lizenz — GQuest
reicht sie nur nicht weiter.

### 3.3 Kennzeichnungspflicht für künftige Übernahmen

Sobald Code aus VRMod übernommen oder erkennbar abgeleitet wird, gilt **zwingend**:

**a)** Die Datei beginnt mit einem Kopfkommentar in genau dieser Form:

```lua
-- Adapted from VRMod (https://github.com/Metastruct/vrmod),
-- original Copyright (c) 2019 Catse, altered version Copyright (c) 2025 Abyss-c0re.
-- Licensed under the zlib licence — see third_party/VRMod-zlib-LICENSE.txt.
-- Altered for GQuest by <Autor>, <Jahr>. This is not the original software.
```

**b)** Die Datei wird zusätzlich in der Tabelle unten eingetragen.

**c)** `third_party/VRMod-zlib-LICENSE.txt` bleibt unverändert im Repository.

**d)** In README und Credits bleibt die Nennung von Catse und Abyss-c0re erhalten.

| Datei (künftig) | VRMod-Ursprung | Art der Veränderung | Autor | Datum |
|---|---|---|---|---|
| _noch keine_ | – | – | – | – |

Ein Eintrag ohne Kopfkommentar oder ein Kopfkommentar ohne Eintrag gilt als Fehler.

---

## 4. Fremde Spielinhalte (nicht im Repository)

| Inhalt | Rechteinhaber | Status |
|---|---|---|
| Garry's Mod | Facepunch Studios | separat über Steam erforderlich, **nicht** enthalten |
| Half-Life 2 Inhalte (Modelle, Texturen, Sounds, Maps) | Valve | separat erforderlich, **nicht** enthalten |
| VR-Waffenmodelle `models/weapons/vr_*.mdl` | eigene bzw. lizenzierte Inhalte des Projektinhabers | **nicht** im Repository, werden lokal bereitgestellt |
| ArcVR-Inhalte | Drittanbieter | **entfernt.** 63 Dateien werden beim Start nach `retired_content/arcvr-20261021/` verschoben |
| H3VR, VRMod-Assets, andere kommerzielle Spiele | jeweilige Rechteinhaber | **nicht** verwendet |

Die Dateiendungen `*.mdl`, `*.vvd`, `*.vtx`, `*.vtf`, `*.vpk`, `*.bsp`, `*.so`, `*.apk`
sind in `.gitignore` ausgeschlossen. Das ist Absicht: es soll technisch unmöglich sein,
Fremdinhalte versehentlich zu committen.

---

## 5. Werkzeuge

| Werkzeug | Rolle | Lizenz |
|---|---|---|
| Rust, Cargo | Rust-Startkomponente | MIT / Apache-2.0 |
| Android NDK, SDK, build-tools | Android-Build | Android SDK License (nicht weitergegeben) |
| Gradle, JDK | Build | eigene Lizenzen (nicht weitergegeben) |
| Python 3 | Build-/Prüfskripte | PSF-Lizenz |
| Lua 5.4 | Testharnesses | MIT |
| KI-Unterstützung | OpenAI Codex, Codebuff | Werkzeug, keine Rechte an Fremdcode |

---

## 6. Was diese Übersicht nicht leistet

- Sie erteilt **keine** Rechte an GDroid, Garry's Mod, HL2 oder VRMod.
- Sie ersetzt keine Rechtsberatung.
- Sie behauptet keine GMod-Addon-Kompatibilität und keine Rechte an Fremdinhalten.
- Sie trifft keine Aussage über die Zulässigkeit einer Store-Veröffentlichung; das hängt
  an GDroid und den Retail-Inhalten und ist vor einem Release gesondert zu klären.
