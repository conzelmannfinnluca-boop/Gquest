# Update-Checkliste (Headset)

Diese Liste beantwortet nach einer Installation vier Fragen: Ist die **richtige Version**
installiert, kam der **Content** an, greift die **Waffenmechanik**, und liefert die
**Hand-Pipeline** noch Posen? Jeder Punkt hat ein klares Kriterium — kein „sieht gut aus".

Voraussetzung: `adb` am PC, Headset per Kabel oder WLAN verbunden (`adb devices` zeigt es).

---

## 1. Version auf dem Gerät

```sh
adb install Gquest.apk
adb shell dumpsys package com.gmodvr.qvrx | grep -E "versionCode|versionName|lastUpdateTime"
```

**Bestanden, wenn** dort `versionCode=75` und `versionName=0.1.30-gquest.2` stehen und
`lastUpdateTime` von gerade ist.

Wenn `INSTALL_FAILED_UPDATE_INCOMPATIBLE` kommt, liegt ein alter Build mit anderem Schlüssel
drauf — erst `adb uninstall -k com.gmodvr.qvrx`, dann installieren (`-k` behält den Content).

---

## 2. Content und Lua angekommen

Einmal Gquest starten, eine Map laden, dann:

```sh
adb shell ls /storage/emulated/0/Android/data/com.gmodvr.qvrx/files/user/vr_content/lua/autorun/server/
adb shell ls /storage/emulated/0/Android/data/com.gmodvr.qvrx/files/user/vr_content/lua/autorun/client/
```

**Bestanden, wenn** `gquest_weapon_mechanics.lua` (server) und `gquest_mech_gestures.lua` sowie
`gquest_wrist_hud.lua` (client) in der Liste stehen. Das Verzeichnis `lua/` wird bei jedem Start
neu geschrieben, deshalb kommen neue Module auch dann an, wenn der restliche Content schon
vorhanden war (`CONTENT … existing=` statt `installed=`).

Alternativ im Log: `CONTENT ready=1 installed=… existing=…` (siehe Schritt 5).

---

## 3. Waffenmechanik greift

Im Spiel eine Pistole aus dem Waffenmenü nehmen. Alles Folgende gibt es auch **ohne Tastatur**:
VR-Menü → **Waffen** → Knöpfe `Magazin`, `Durchladen`, `Nachladen`, `Sicherung`, `Zustand`,
`Haende`. Das Panel bleibt dabei offen, damit mehrere Aktionen hintereinander gehen.

Oder in der Konsole:

```
gquest_mech_state
```

**Bestanden, wenn** eine Zeile `GQUEST_MECH STATE class=… kind=magazine … chamber=… mag=…`
kommt. Danach:

```
gquest_mech_mag      # Magazin fällt heraus, Restmunition bleibt
gquest_mech_mag      # wieder einsetzen — lädt NICHT durch
gquest_mech_rack     # jetzt ist eine Patrone im Lager
```

Kontrolle nach jedem Schritt mit `gquest_mech_state`. Erwartung: nach dem Einsetzen ist
`chamber=0`, nach dem Durchladen `chamber=1`, und `chamber + mag` bleibt die Summe, die vorher
im Clip stand.

Einmal schießen und danach `gquest_mech_state`: `mag` muss um genau eins kleiner sein.
Bei leerer Kammer (nach dem Schuss bei Pumpe/Bolzen) darf der Schuss **klicken**, nicht treffen.

**Wenn gar keine `GQUEST_MECH`-Zeile kommt:** Modul nicht geladen (Schritt 2 prüfen).
**Wenn `GQUEST_MECH write refused` kommt:** die Waffe folgt der Engine, nicht dem Modell — das
ist der Fall, den ich brauche (mit `class` und `reason`).

---

## 4. Hand-Pipeline liefert Posen

VR-Menü → **Waffen** → Knopf `Haende`, oder in der Konsole:

```
gquest_hands_state
```

**Bestanden, wenn** für beide Hände `pos=… ang=… vel=…` erscheint und sich die Werte ändern,
wenn du die Hand bewegst. `drops=` zählt Proben, die unbrauchbar waren und durch die letzte Pose
ersetzt wurden — einige wenige sind normal, dauerhaft steigende Werte bei einer Hand bedeuten,
dass deren Tracking wegbricht (die Hand bleibt dann stehen, statt zu verschwinden).

---

## 5. Log sammeln und auswerten

```sh
adb logcat -c
# Gquest starten, Map laden, Pistole nehmen, schießen, Magazin, Durchladen
adb logcat -d > quest-update.log
python3 Gquest-Hybrid/tools/evaluate_hardware_log.py quest-update.log
```

**Bestanden, wenn** kein `[FEHLER]` erscheint und bei `Mechanik` mindestens ein Schuss verbucht
ist. `[UNBEKANNT]` heißt „diese Zeile fehlt" — nicht „in Ordnung". `[warnung]` ist ein Hinweis,
kein Abbruch (z. B. eine VR-Aktion, die es in dieser Session nicht gibt).

---

## 6. Was ich zum Weiterbauen brauche

Bei einem Problem bitte diese vier Dinge:

1. `quest-update.log` (die Ausgabe von Schritt 5, gern die ganze Datei)
2. die Ausgabe von `adb shell dumpsys package com.gmodvr.qvrx | grep -E "versionCode|versionName"`
3. welche Waffe (`class=`) und welcher Schritt (Schritt 3) nicht wie erwartet war
4. bei der Hand: was man **sieht** — verschwindet sie, ist sie verdreht, hängt sie hinterher,
   oder stimmen die Finger nicht

Damit lässt sich jede Zeile einer echten Ursache zuordnen, statt zu raten.
