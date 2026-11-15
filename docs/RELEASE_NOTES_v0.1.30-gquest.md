# GQuest 0.1.30-gquest — Release-Notes

## Was diese Version ist

Ein Overlay auf die **offizielle GDroid 0.1.30** (`com.gmodvr.qvrx`, arm64-v8a, Quest 3/3S).
Keine eigenständige App: Engine, Renderer und Spielinhalte kommen unverändert aus dem
Basispaket, dazu kommen eigener Launcher, eigene Bridge und eigenes Lua.

**Dieses Repository enthält kein APK.** Es enthält die Quellen und die Anleitung, um eines zu
bauen. Warum: Basis-APK, Retail-Inhalte und Signaturschlüssel dürfen nicht weitergegeben
werden. Bauanleitung in `BUILD.md`, Abschnitte 3 und „Einrichtung auf einem frischen Rechner".

## Trägerbestätigt auf Quest 3

Alle Aussagen in diesem Abschnitt stammen von dir selbst im Headset, nicht aus einem Test auf
meiner Seite. Belege: `docs/Gquest-HL2-only-verification.json`,
`docs/Gquest-HL2-reload-verification.json`, `docs/Gquest-HL2-damage-verification.json`.

**Nachladen und Schießen — alle sieben nativen HL2-Feuerwaffen:**

| Waffe | Bestätigung |
|---|---|
| Pistole | Einsetzen, Durchladen, Schießen funktionieren |
| SMG | Nachladen und Schießen funktionieren |
| Shotgun | Patronen laden, Durchladen, Schießen funktionieren |
| AR2, .357, Crossbow, RPG | „alle vier funktionieren" (manuelles Aufnehmen, Einsetzen, Durchladen soweit zutreffend, Schießen) |

Die **vollständige native Kette** aus Magazin, Reserve, Kammer und Zustand ist als Log
**nur für die Pistole** hinterlegt. Die anderen sechs sind Trägerberichte, kein Mitschnitt.

**Treffer und Schaden:** Shotgun, AR2, .357, Crossbow und RPG bestätigt; für Pistole und
Shotgun zusätzlich native Schadenswerte und sinkende NPC-Gesundheit im Log beobachtet.

**Haltung und Ausrichtung:** Pistole korrekt ausgerichtet; SMG zweihändig stabil und einhändig
richtig, nachdem die Griff-Caches aus den tatsächlichen Modell-Attachments erneuert wurden;
Brechstangen-Richtung je Waffenklasse korrigiert und bestätigt.

**ArcVR ist entfernt:** 63 früher installierte Dateien werden beim ersten Start außerhalb des
Spielordners gesichert, im Paket ist keine ArcVR-Klasse mehr enthalten.

## Gebaut und automatisch geprüft — ohne Headset

```
python3 Gquest-Hybrid/tools/build.py --tests
```

41 Prüfungen, 11 Gruppen, Exit 0: 12 C++-Grenztests, 9 Rust-Unit-Tests, C++/Rust-ABI-Smoke,
Bridge-Cross-Compile für `aarch64-linux-android29` mit `-Wall -Wextra -Werror`,
6 Werkzeug-Selbsttests, 12 Lua-Harnesses.

Neu in dieser Version:

- **Handposen-Glättung** mit Stufen Aus / Mild (30 ms) / Stark (60 ms), im Menü wählbar und im
  Geräteprofil gespeichert. Der Faktor kommt aus dem geklemmten Frame-Schritt, 36 Hz und 72 Hz
  enden am selben Punkt. Der Kopf bleibt bewusst ungeglättet.
- **Einstellungsmenü in zwei Spalten**: 898 px Inhalt bei 970 px nutzbar, kein Scrollen auf dem
  Referenzschirm.
- **Frame-Zeit-Guard**: rohe Frame-Zeit ist außerhalb des Performance-Samplers verboten
  (`frame_policy.py`), damit keine weitere Stelle einen Stall einfach integriert.

## Ausdrücklich nicht bestätigt

Diese Liste ist vollständig und absichtlich unangenehm — nichts davon ist „fertig", nur weil es
kompiliert.

| Offen | Stand |
|---|---|
| Quest 3S | **kein Hardwaretest**, alle Aussagen oben sind von einer Quest 3 |
| Handglättung im Headset | **nicht gespürt**: 30/60 ms sind Vorgaben, keine Messung; ob „Stark" zu träge ist, entscheidet das Headset |
| Menü-Layout im Headset | **nicht gesehen**: 898 px und die Umbruchschätzung von 28 Zeichen sind gerechnet |
| Frametimes auf dem Gerät | Instrumentierung fertig, **keine Messung** auf Hardware |
| Sitzend/Stehend | wird gespeichert, wirkt aber **erst mit dem Core-Umstieg** (Entscheidung E1), heute ohne Einfluss auf das Spiel |
| Magazin-Detailkette außer Pistole | nur Trägerbericht, kein Mitschnitt |
| Segmentzugehörigkeit gepinnter Adressen | offen, braucht `libclient.so` |
| 1:1-Parität zu PCVR/Addons | nicht erreicht, nicht behauptet |
| Das APK selbst | in diesem Repository **nicht gebaut**; Reproduzierbarkeit gegeben die privaten Eingaben, nicht aus dem Repo allein |

## Selbst bauen

```sh
python3 Gquest-Hybrid/tools/build.py --check            # was fehlt, mit Beschaffungsweg
python3 Gquest-Hybrid/tools/verify_base_apk.py         # lieferte Basis-APK gegen alle Pins
python3 Gquest-Hybrid/tools/build.py --tests   # 41 Prüfungen, ohne private Daten
python3 Gquest-Hybrid/tools/build.py           # volles APK
```

Ergebnis: `Gquest-Hybrid/dist/Gquest-Rust-GDroid.apk` und `verification.json`. Die
`verification.json` gehört zu einem Release dazu — sie belegt den Digest und dass sich gegenüber
der Basis nur `AndroidManifest.xml`, `classes.dex` und `lib/arm64-v8a/libclient.so` geändert
haben.

## Quellen dieses Releases

- Quellarchiv `Gquest-0.1.30-gquest-<commit>-source.zip`, erzeugt mit `git archive` aus genau
  dem Commit, den der Tag nennt. Die Prüfsumme steht in der Release-Beschreibung und in der
  beiliegenden `SHA256SUMS` — sie wird **nicht** in dieser Datei wiederholt, weil sie sich mit
  jedem Commit ändert und eine eingetragene Zahl dann veraltet wäre.
- Lizenz: MIT für den eigenen Code (`LICENSE`), Fremdanteile in `THIRD_PARTY_NOTICES.md`
