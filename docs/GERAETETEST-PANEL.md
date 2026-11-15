# Gerätetest: Waffenpanel und Mechanik-Zeilen

Kurze Anleitung für den ersten Lauf im Headset. Sie hakt genau die Zeilen ab, die das Panel und
die Mechanik seit `0.1.30-gquest.2` schreiben — nichts anderes. Die breite Abnahme steht in
[UPDATE-CHECKLISTE.md](UPDATE-CHECKLISTE.md), die Regeln der Mechanik in
[H3VR-WAFFENMECHANIK.md](H3VR-WAFFENMECHANIK.md).

Voraussetzung: `adb` am PC, Headset verbunden (`adb devices`), `Gquest.apk` installiert
(`versionCode=75`, `versionName=0.1.30-gquest.2`).

---

## 0. Log vorbereiten

```sh
adb logcat -c
# Gquest starten, Map laden, dann die Schritte unten
adb logcat -d > quest-panel.log
```

Am Ende auswerten:

```sh
python3 Gquest-Hybrid/tools/evaluate_hardware_log.py quest-panel.log
```

**Bestanden, wenn** kein `[FEHLER]` erscheint, bei `Mechanik` mindestens ein Schuss verbucht ist
und `Waffenmenue` die letzte Wahl mit derselben Ausrüstung zeigt. `[UNBEKANNT]` heißt „Zeile
fehlt", nicht „in Ordnung".

---

## 1. Panel öffnen

VR-Menü → **Waffen**.

| | erwartet |
|---|---|
| Panel | Zeile über den Knöpfen: `Waffe: weapon_pistol - Kammer 1, Magazin 17/18, Sicherung aus, Verschluss zu` (oder die Waffe, die du zuletzt hattest) |
| Log | `GQUEST_WEAPON_MENU opened` |

Steht dort `Waffe: nichts in der Hand`, ist keine Waffe aktiv — erst eine nehmen, dann erneut
öffnen. Steht dort `keine Mechanik-Daten`, kam keine Antwort vom Server: dann Schritt 8 prüfen.

## 2. Waffe wählen (Bestätigung)

Im Panel eine Pistole anklicken.

| | erwartet |
|---|---|
| Panel | sofort `Waffe: Pistole wird ausgeruestet ...`, danach die Zahlen, dann schließt das Panel |
| Log | `GQUEST_WEAPON_MENU selected=weapon_pistol`, `GQUEST_HL2 equipped=weapon_pistol`, `GQUEST_MECH action=init class=weapon_pistol …` |

Bleibt `wird ausgeruestet ...` länger als eine Sekunde stehen, fehlt die `equipped`-Zeile im Log —
das ist der Befund, den der Auswerter als Warnung meldet.

## 3. Schießen

Zweimal abdrücken, Panel danach wieder öffnen.

| | erwartet |
|---|---|
| Panel | `Kammer 1, Magazin 15/18` (zwei Schüsse weniger) |
| Log | zwei `GQUEST_MECH action=fire class=weapon_pistol …`, Summe jeweils genau eins kleiner |

## 4. Die sechs Knöpfe

`Magazin`, `Durchladen`, `Nachladen`, `Sicherung`, `Zustand`, `Haende` — je einmal drücken, das
Panel bleibt offen.

| Knopf | erwartet im Panel | erwartet im Log |
|---|---|---|
| `Magazin` | `Magazin draussen`, `Verschluss offen` | `action=mag-out` |
| `Magazin` (nochmal) | Magazin wieder eingesetzt | `action=mag-in` |
| `Durchladen` | Kammer gefüllt, Magazin eins weniger | `action=rack` |
| `Nachladen` | Magazin voll aus der Reserve | `action=reload` |
| `Sicherung` | `Sicherung an` / `Sicherung aus` | `action=safety` |
| `Zustand` | Zeile bleibt, Werte stimmen | `GQUEST_MECH STATE class=… capacity=… chamber=… mag=…` |
| `Haende` | unverändert | `GQUEST_HANDS hand=… state=…` |

## 5. Waffe ohne Mechanik

Brechstange, Gravity Gun oder Granate nehmen, Panel öffnen.

| | erwartet |
|---|---|
| Panel | `Waffe: Brechstange (weapon_crowbar) - hat keine Mechanik, nur Pistole, .357, SMG, AR2, Schrotflinte, Armbrust, RPG` |
| Log | `GQUEST_MECH state: no supported weapon class=weapon_crowbar` — das ist **erwartet**, kein Fehler |

## 6. Wechsel ohne Panel

Panel schließen, im Spiel die Waffe wechseln (andere Waffe nehmen), Panel sofort wieder öffnen.

| | erwartet |
|---|---|
| Panel | steht schon beim Öffnen auf der neuen Waffe, nicht auf der alten |
| Log | **keine** neue `GQUEST_MECH`-Zeile für den Wechsel (der Push ist still) |

## 7. Lesezeit

VR-Einstellungen → `Waffen-Lesezeit: 0,30 s (klicken)` einmal auf `0,00 s` und einmal auf
`0,60 s` stellen, dazwischen je eine Waffe wählen.

| | erwartet |
|---|---|
| Panel | bei `0,00 s` schließt es sofort, bei `0,60 s` bleibt die bestätigte Zeile sichtbar |
| Profil | `gquest_vr_profile.txt` im Spiel-Datenverzeichnis enthält `read=0` bzw. `read=600` |

## 8. Wenn nichts ankommt

Panel zeigt dauerhaft `keine Mechanik-Daten` oder `wird ausgeruestet ...`:

```sh
adb logcat -d | grep -E "GQUEST_MECH|GQUEST_WEAPON_MENU|GQUEST_HL2"
```

- keine `GQUEST_MECH`-Zeile → Servermodul nicht geladen (Schritt 2 der Update-Checkliste).
- `GQUEST_WEAPON_MENU selected=…` ohne `GQUEST_HL2 equipped=…` → der Klick kam nicht am Server an
  (Einzelspieler? Waffe verweigert?).
- `GQUEST_MECH state: unreadable engine state class=…` → der Engine-Wert ist unbrauchbar; die
  Mechanik lässt die Waffe dann absichtlich in Ruhe.

---

## Was ich zurückbrauche

1. `quest-panel.log` (oder die Ausgabe des Auswerters).
2. Drei Eindrücke, die kein Log liefert: Fühlt sich die Lesezeit richtig an? Trifft man die
   Knöpfe im Panel sicher? Wirkt der Waffenwechsel im Panel verzögert?
3. Gerät (Quest 3 / 3S) und ob es beim ersten oder zweiten Versuch klappte.

Nicht Teil dieses Tests: Gesten (Support-Hand-Rack, Magazin-Eject) und ob `EntityFireBullets` bei
nativen HLVR-Waffen greift — beides steht in [H3VR-WAFFENMECHANIK.md](H3VR-WAFFENMECHANIK.md)
und bleibt bis zum Gerätelauf NOT TESTED.
