# Messprotokoll: Performance-Profile auf Quest 3 und Quest 3S

Stand: 14. November 2026

**Status: Verfahren fertig, nie durchgeführt.** Es liegt kein Lauf auf Hardware vor.
Alles hier beschreibt, *wie* gemessen wird; nichts hier ist ein Messergebnis.
Schwellenwerte in Abschnitt 7 sind Vorschläge, keine empirisch belegten Grenzen.

---

## 1. Zweck

Die drei Bildprofil-Stufen (Leistung / Ausgewogen / Schärfer) sollen je Gerät
vergleichbar werden, damit „läuft flüssig" durch Zahlen ersetzt wird und die
Empfehlungen in `gquest_vr_profiles.lua` belegbar sind.

Nicht Gegenstand: GPU-Zeit, Bildqualität, Vergleich Quest 3 gegen Quest 3S. Jede
Messreihe gilt für **ein** Gerät; zwischen Geräten wird nichts verglichen, weil die
Panels unterschiedlich sind und die Stufen bewusst verschieden.

## 2. Was dieses Protokoll nicht beweisen kann

Diese Grenzen sind keine Nebenbemerkung, sondern bestimmen, wie die Zahlen gelesen
werden dürfen:

- **Keine GPU- oder CPU-Zeit.** GMod-Lua liefert sie nicht. Das HUD gibt dort bewusst
  nichts aus, statt Zahlen zu erfinden.
- **Keine Draw Calls, keine Dreiecke.** Aus demselben Grund nicht messbar.
- **`fps_*` sind App-Frames, nicht die wahrgenommene Bildrate.** Lässt der Compositor
  die App mit 45 Hz laufen und rechnet auf 90 hoch, zeigt das Headset 90, das CSV
  zeigt 45. Umgekehrt kaschiert Reprojektion Ruckler. Deshalb wird in jedem Lauf
  notiert, ob Reprojektion aktiv war (Abschnitt 8).
- **`width,height` sind `ScrW/ScrH` des Clients.** Ob das dem Eye-Buffer-Maß
  entspricht, ist unverifiziert. Die Spalten taugen als Konsistenzprüfung („hat sich
  während des Laufs nichts geändert"), nicht als Beweis, dass eine Stufe gegriffen hat.
- **Es gibt keinen Logbeleg für die aktive Stufe.** Deshalb Prüfschritt 3.4.
- **FFR ist nicht messbar.** `vr_ffr_level` wird gesetzt, aber ob und wie stark die
  Reduktion greift, ist von außen nicht sichtbar. Der Vergleich „FFR 1 gegen FFR 3"
  ist deshalb nur über die Frametimes möglich, nie direkt.

## 3. Voraussetzungen

| Punkt | Vorgabe |
|---|---|
| Gerät | ein Gerät pro Messreihe, alle Läufe darauf |
| Build | gleiche APK für alle Läufe, SHA-256 notieren |
| Inhalt | gleiche Map, gleiches Save, gleiche Addons |
| Akku | ≥ 80 %, **nicht** am Ladegerät (Laden heizt) |
| Haltung | stehend, ruhiger Raum, Controller abgelegt |
| Profilwechsel | Bildprofil gilt erst nach Neustart → jede Stufe = ein vollständiger Neustart |
| Sampling | `gquest_perf_enabled 1`, `gquest_perf_window 512`, `gquest_perf_interval 5` |

Paketpfad für alle `adb`-Befehle:
`/sdcard/Android/data/com.gmodvr.qvrx/files/user/garrysmod/data/gquest/`

## 4. Messgrößen

`perf.csv` hat 17 Spalten, Header genau einmal:

| Spalte | Bedeutung | Rolle in der Auswertung |
|---|---|---|
| `t` | `RealTime` in Sekunden (Map-Laufzeit, **kein** Wandzeitstempel) | nur zur Orientierung |
| `fps_avg` | 1000 / `ms_avg` | **nicht** als Kennzahl — Mittelwert verdeckt Ruckler |
| `fps_1pct_low` | 1000 / Mittel der langsamsten 1 % | Kennzahl (Ausreißer) |
| `ms_avg`, `ms_p50` | Mittel bzw. Median der Fenster-Frametimes | Kontext |
| `ms_p95` | 95-%-Perzentil der Fenster-Frametimes | **Hauptkennzahl** |
| `ms_p99`, `ms_max` | oberes Ende | Plausibilitätsprüfung |
| `hitches` | Frames über `max(p50×2, Budget×1,5)` | Kennzahl (pro Minute) |
| `under_budget_pct` | Anteil Frames ≤ `1000/target_hz` | Kennzahl |
| `tick_hz`, `entities` | Tickrate, Entitätszahl | **Beweis, dass die Szene gleich war** |
| `lua_kb`, `ping_ms` | Lua-Speicher, Ping | Störgröße, notieren |
| `width`, `height` | `ScrW/ScrH` | Konsistenzprüfung |
| `target_hz` | Rate aus Zeile 3 des Profils | Bezugsgröße für das Budget |

Warum `ms_p95` und nicht `fps_avg`: der Mittelwert über 512 Frames wird von einem
einzigen 200-ms-Ausschlag kaum bewegt, fühlt sich aber genau so an wie er ist —
schlecht. `ms_p95` und `fps_1pct_low` beschreiben die Frames, die man merkt.

Ein `hitch` ist bewusst **nicht** dasselbe wie „Budget verpasst". Ein Frame knapp
über dem Budget ist Last, ein Frame über dem doppelten Median ist ein Aussetzer. Die
Instrumentierung trennt beides, also tut die Auswertung es auch.

## 5. Ablauf eines Laufs

1. Profil im VR-Menü auf die zu messende Stufe stellen, speichern, **vollständig
   neu starten**, bis zur gewohnten Szene laden.
2. Logcat mitschreiben:
   `adb logcat -c && adb logcat -v time > runs/<name>-logcat.txt &`
3. Konsole: `gquest_perf_window 512` (löst einen Reset aus), dann
   `gquest_perf_reset`, `gquest_perf_csv 1`, `gquest_perf_interval 5`.
4. **Prüfen, dass die Stufe aktiv ist:** `vr_eye_resolution` in der Konsole abfragen
   und den zurückgemeldeten Wert ins Aufnahmeblatt schreiben. Zusätzlich müssen
   `width`/`height` über den ganzen Lauf konstant bleiben — ändern sie sich, war die
   Szene nicht stabil und der Lauf ist ungültig.
5. 30 s Warmlauf (Shader, erste Frames), danach `gquest_perf_reset`. Der Warmlauf
   gehört nicht in die Messung.
6. 5 Minuten definierte Szene, immer dieselbe: 60 s still stehen, 60 s langsam einmal
   um die eigene Achse drehen, 60 s auf einen festen Punkt zielen, 60 s laufen, 60 s
   still. Die Bewegung ist Teil der Last und muss zwischen allen Läufen gleich sein.
7. `gquest_perf_report` → schreibt `perf_summary.txt` und gibt die Zeilen in die
   Konsole (landet im Logcat).
8. CSV ziehen und **danach löschen**:
   `adb pull /sdcard/.../gquest/perf.csv runs/<name>.csv`
   `adb shell rm /sdcard/.../gquest/perf.csv`
   Das Löschen ist Pflicht: `t` ist Map-Laufzeit, kein Datum — zwei Läufe in einer
   Datei lassen sich nicht mehr sauber trennen.
9. 3 Minuten Pause vor dem nächsten Lauf (Thermik, siehe Abschnitt 9).

## 6. Versuchsplan

- 3 Stufen × 3 Wiederholungen = **9 Läufe pro Gerät**, rund 75 Minuten inklusive Pausen.
- Reihenfolge gespiegelt, damit Thermik-Drift nicht systematisch eine Stufe trifft:
  `A B C C B A A B C` (A = Leistung, B = Ausgewogen, C = Schärfer).
- Zwischen zwei Läufen mindestens 3 Minuten, gleiche Umgebungstemperatur im Raum.
- Bricht ein Lauf ab (App-Neustart, Hitze-Warnung, unruhige Szene): **verwerfen und
  wiederholen**, nicht mitteln und nicht als Ausreißer wegrechnen.

## 7. Auswertung

1. Pro Lauf: Spalten aus `runs/<name>.csv`, je Kennzahl den Median über alle Zeilen
   des Laufs (jede Zeile ist ein Fenster über 512 Frames).
2. Pro Stufe: Median über die 3 Läufe, plus Spannweite (min…max).
3. **Rauschgrenze:** Überlappen sich die Spannweiten zweier Stufen, gilt der
   Unterschied als **nicht gezeigt**. Dann mehr Wiederholungen — nicht „ungefähr
   gleich" behaupten und nicht die Ausreißer entfernen.
4. **Entscheidungsregel** (Vorschlag; Budget = `1000/target_hz`, also 13,89 ms bei
   72 Hz und 11,11 ms bei 90 Hz):

| Ergebnis | Bedingung |
|---|---|
| geeignet | Median `ms_p95` ≤ Budget **und** `hitches` ≤ 1 pro Minute |
| grenzwertig | `ms_p95` ≤ 1,15 × Budget, Rest wie oben |
| ungeeignet | darüber, oder wiederkehrende Hitches |

Auswertung reproduzierbar, ohne Handarbeit:

```python
import glob, pandas as pd
df = pd.concat([pd.read_csv(f).assign(run=f) for f in glob.glob("runs/*.csv")])
per_run = df.groupby("run").agg(p95=("ms_p95", "median"), worst=("ms_p95", "max"),
                                low=("fps_1pct_low", "median"), hitches=("hitches", "median"),
                                budget=("under_budget_pct", "median"))
print(per_run)
print("p95 Median", per_run.p95.median(), "Spannweite", per_run.p95.min(), "-", per_run.p95.max())
```

## 8. Aufnahmeblatt

Ein Block pro Lauf, leer auszufüllen — die Auslassungspunkte sind Platzhalter, keine
Messwerte:

| Feld | Wert |
|---|---|
| Lauf | `<geraet>-<stufe>-<n>` |
| Gerät / Build-SHA256 | … |
| Stufe / `target_hz` | … / … |
| `vr_eye_resolution` zurückgemeldet | … |
| `ms_p50` / `ms_p95` | … / … |
| `fps_1pct_low` | … |
| `hitches` pro Minute | … |
| `under_budget_pct` | … |
| `entities` / `tick_hz` | … / … |
| Reprojektion aktiv (j/n) | … |
| Besonderheiten | … |

## 9. Störgrößen

| Störgröße | Wirkung | Gegenmittel |
|---|---|---|
| Thermik | Quest drosselt nach einigen Minuten; im CSV unsichtbar | 3 min Pause, gespiegelte Reihenfolge, `adb shell dumpsys thermalservice` mitschreiben |
| Laden | heizt zusätzlich | während der Läufe nicht laden |
| Reprojektion | verfälscht `fps_*` in beide Richtungen | im Aufnahmeblatt notieren, nie zwischen Läufen wechseln |
| Content/Addons | andere Last bei gleicher Stufe | gleiches Save, gleiche Addons, `entities` als Kontrolle |
| Shader-Kompilierung | Hitches beim ersten Betreten | Warmlauf verwerfen |
| Ping | nur bei Multiplayer relevant | Einzelspieler messen |
| FFR | nicht messbar | nur indirekt über Frametimes vergleichen |

## 10. Ablage der Ergebnisse

```
runs/<geraet>-<stufe>-<n>.csv          eine Datei pro Lauf, nie anhängen
runs/<geraet>-<stufe>-<n>-logcat.txt
runs/<geraet>-<stufe>-<n>-thermal.txt
docs/measurements/<geraet>.md          Zusammenfassung nach der Auswertung
```

`runs/` gehört nicht ins Repository (Rohdaten, groß). In `docs/measurements/` kommt
nur die ausgewertete Tabelle mit Verweis auf die Rohdateien.

## 11. Wann der Projektstatus wechselt

`Performance-Messung auf Quest 3` bleibt **NOT TESTED**, bis 9 gültige Läufe
vorliegen, die Entscheidungsregel aus Abschnitt 7 angewendet ist und die Tabelle in
`docs/measurements/` steht. Ein einzelner Lauf, ein Screenshot des HUD oder ein
gefühlter Eindruck sind kein Nachweis — dafür existiert dieses Protokoll.
