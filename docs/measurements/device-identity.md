# Geräteidentität: echte `Build.MODEL`-Werte

Stand: 14. November 2026

**Status: nicht erfasst.** Es lag kein Headset und kein ADB-Gerät vor. Die Tabelle unten
ist leer, weil sie leer ist — nicht, weil die Werte unbekannt wären, sondern weil sie
niemand gemessen hat. Bis das geschieht, bleibt die Geräteerkennung im Projektstatus auf
**NOT TESTED**.

## Warum dieser Punkt nicht geraten werden darf

Meta beschreibt einen **Compatibility Mode**: Horizon OS prüft beim Start den
`com.oculus.supportedDevices`-Eintrag im Manifest der App. Fehlt das physische Headset
dort, melden Geräte-Identifikations-APIs ein **älteres Modell** statt der echten
Hardware. Meta schreibt dazu ausdrücklich:

> „Don't use `android.os.Build.MODEL` to infer whether compatibility mode is active.
> Don't use it, or any single reported device value, to decide whether a feature is
> available."

Quelle: <https://developers.meta.com/horizon/documentation/native/android/os-compatibility-mode>

Für GQuest heißt das: ein Wert, den die App selbst meldet, ist **kein Beweis** für die
Hardware. Eine Quest 3S könnte sich als Quest 3 melden, und die Erkennung würde dann
selbstsicher das falsche Profil wählen — schlimmer als keine Erkennung, weil das Menü
„passt zur Auswahl" anzeigen würde.

Deshalb vergleicht die Erfassung **zwei Quellen**:

| Quelle | Wie | Aussagekraft |
|---|---|---|
| physisch | `adb shell getprop ro.product.model` / `ro.product.device` | läuft außerhalb des App-Prozesses, nicht vom Compatibility Mode betroffen |
| in-app | Logzeile der Bridge `DEVICE detected=… model='…' device='…'` | genau das, was die Erkennung tatsächlich sieht |

Stimmen beide überein, ist die Erkennung für dieses Gerät belegt. Weichen sie ab, ist
der Compatibility Mode die wahrscheinlichste Ursache und das Manifest der Basispakets zu
prüfen.

## Erwartete Werte (aus der Dokumentation, **nicht** auf unserem Gerät bestätigt)

Die `supportedDevices`-IDs sind von Meta dokumentiert. Die `Build.DEVICE`-Codenamen sind
Community-Wissen und **nicht** von Meta veröffentlicht — sie sind deshalb nur ein
zusätzlicher Fallback im Klassifizierer, nie die Hauptquelle.

| Gerät | `Build.MODEL` (erwartet) | `Build.DEVICE` (berichtet) | `supportedDevices` |
|---|---|---|---|
| Meta Quest 3 | `Quest 3` | `eureka` | `quest3` |
| Meta Quest 3S | `Quest 3S` | `panther` | `quest3s` |
| Meta Quest 2 | `Quest 2` | `hollywood` | `quest2` |
| Meta Quest Pro | `Quest Pro` | `seacliff` | `questpro` |

Meta nennt außerdem die Schreibweise `Oculus_Quest_2` als möglichen gemeldeten Wert.
Der Klassifizierer akzeptiert deshalb beide Formen (`Quest 3S` und `Oculus_Quest_3S`) und
lehnt Fast-Treffer wie `Quest 30` weiterhin ab — geprüft in `tests/device_model.cpp`.

## Vorgehen (etwa 5 Minuten pro Gerät)

1. Headset per USB verbinden, Entwicklermodus aktiv, `adb devices` zeigt es.
2. Physische Werte und In-App-Wert in einem Lauf erfassen:

   ```sh
   python3 Gquest-Hybrid/tools/capture_device.py \
       --record docs/measurements/device-identity.md
   ```

3. Ohne ADB (Werte von Hand abgelesen):

   ```sh
   python3 Gquest-Hybrid/tools/capture_device.py --model "Quest 3S" --device panther
   ```

4. Urteil in der Ausgabe lesen:

| Urteil | Bedeutung | Nächster Schritt |
|---|---|---|
| `konsistent` | Erkennung stimmt mit der Hardware überein | Wert ist belegt, Zeile bleibt |
| `In-App-Wert fehlt` | App lief nicht oder Logcat war leer | App starten, Lauf wiederholen |
| `WIDERSPRUCH` | App meldet ein anderes Modell | Manifest prüfen (siehe unten) |
| `App erkennt das Geraet nicht` | Modellzeichenkette unbekannt | Zeichenkette hier eintragen und Klassifizierer erweitern |

5. Manifest der installierten App prüfen, wenn das Urteil `WIDERSPRUCH` lautet:

   ```sh
   aapt2 dump xmltree <basis.apk> --file AndroidManifest.xml | grep -i supportedDevices
   ```

   Erwartet: `quest2|questpro|quest3|quest3s`. Fehlt `quest3s`, läuft jede 3S im
   Compatibility Mode.

## Offener Punkt: das Manifest der GDroid-Basis

Ob `com.oculus.supportedDevices` im Basispaket `quest3s` enthält, ist **ungeprüft** — die
APK liegt hier nicht vor (siehe `PROJECT_STATUS.md`, Voraussetzungen). Seit der
Manifest-Prüfung im Packaging ist das aber kein stilles Risiko mehr:

- `work/build_quest_lab.py` liest den fertigen Eintrag **zurück** und bricht ab, wenn er
  fehlt, `quest3s` nicht enthält oder doppelt vorhanden ist.
- Steht der Eintrag bereits im Basispaket, wird sein Wert **zusammengeführt** statt ein
  zweiter Eintrag angehängt (bei zwei Einträgen behält Android einen beliebigen).
- Die Lese-/Zusammenführungslogik ist in `overlay_manifest.py` ohne Android-SDK getestet;
  gegen die echte Basis-APK ist sie nie gelaufen.

Zur Laufzeit liest die Bridge denselben Wert aus dem eigenen Manifest zurück
(`DEVICE detected=… supported='…'`) und vergleicht ihn mit dem klassifizierten Modell. Zwei
Fälle werden als Warnung geloggt, beide **ohne** das Profil zu ändern:

| Logzeile | Bedeutung |
|---|---|
| `DEVICE WARN model <id> is not declared …` | Das erkannte Gerät steht nicht in der Liste — die App läuft womöglich im Compatibility Mode und meldet ein anderes Headset. |
| `DEVICE WARN manifest declares quest3 but not quest3s …` | Ein echtes Quest 3 und eine 3S im Compatibility Mode melden beide `Quest 3`; das Profil kann zum falschen Gerät gehören. |

`supported='(unreadable)'` heißt: Manifest nicht lesbar — dann schweigt der Vergleich
absichtlich, weil es nichts zu vergleichen gibt.

Bis das geklärt ist, ist die Geräteerkennung eine Heuristik mit Sicherheitsnetz, keine
Zusage:

- unbekanntes Modell → gespeichertes Profil bleibt unangetastet
- erkannter Widerspruch zur Auswahl → Statuszeile im Menü zeigt ihn an
- der Nutzer kann jederzeit manuell umstellen

## Erfasste Werte

Wird von `capture_device.py` geschrieben; bislang keine Zeile, weil kein Gerät vorlag.
