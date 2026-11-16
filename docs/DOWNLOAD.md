# Download: welche APK, welcher Weg

Alle Dateien liegen im Ordner `outputs/` des Arbeitsbereichs. Es gibt drei Formen derselben
Version — die Wahl hängt nur davon ab, wie groß ein Download sein darf (Freebuff bricht bei
**256 MB pro Datei** ab).

| Variante | Datei | Größe | Wofür |
|---|---|---|---|
| **Slim (empfohlen zum Direkt-Download)** | `Gquest-0.1.30-gquest.2-slim.apk` | 139.464.174 Bytes (133 MB) | direkt herunterladen, direkt `adb install` — **ohne** die 14 großen 4K-Waffentexturen |
| **Voll, geteilt** | `Gquest-0.1.30-gquest.2.apk00.part` + `…apk01.part` | 209.715.200 + 73.741.555 Bytes | alles inklusive Texturen; zwei Teile herunterladen und am PC zusammenfügen |
| Voll, ein Teil | `Gquest.apk` / `Gquest-0.1.30-gquest.2.apk` | 283.456.755 Bytes | nur für Kanäle ohne Größengrenze |

Version immer gleich: `versionCode 75`, `versionName 0.1.30-gquest.2`.

## Prüfsummen

```
86580e22865b65c7de7880838653f7d614b96b27d98ea9056b968aab00676750  Gquest.apk (voll)
86580e22865b65c7de7880838653f7d614b96b27d98ea9056b968aab00676750  Gquest-0.1.30-gquest.2.apk (voll, gleiche Datei)
5b7855a21f3acf575416e28015de9dd90066eb092854365b113f21d39d340828  Gquest-0.1.30-gquest.2.apk00.part
1b6dcbdf83fad1ba1c8ca6ff4c9bd0c35484fc4c40fa4222a77e141da96a3e66  Gquest-0.1.30-gquest.2.apk01.part
2f78c94a7f32f96d85571b3a30161f630519fa4641913a663d94e80ec434fb67  Gquest-0.1.30-gquest.2-slim.apk
69708165e66684972fadde0c1130009bb003c09ce514ff4ba8090023212efe84  Gquest-slim.apk00.part
dfe036d2ad60f07579acb7cd04bbab603ca448e0f7a41ec7cf902e4c3bdb56c9  Gquest-slim.apk01.part
```


Prüfen mit `sha256sum <datei>` (Linux/macOS) oder `certutil -hashfile <datei> SHA256` (Windows).

## Slim auch in zwei Teilen (falls selbst 133 MB nicht durchgehen)

`Gquest-slim.apk00.part` (73.400.320 Bytes) + `Gquest-slim.apk01.part` (66.063.854 Bytes),
zusammenfügen wie unten, Ergebnis muss SHA256 `2f78c94a…4a4c37` haben.

## Slim direkt installieren

```sh
adb install -r Gquest-0.1.30-gquest.2-slim.apk
```

Enthält 218 Modelle, 114 Materialien (alle außer den 14 Dateien über 10 MB), 12 Waffenscripts und
die 18 Lua-Dateien. Die fehlenden 14 Dateien sind ausschließlich die großen 4K-Waffentexturen
(`materials/models/weapons/…`); Modelle, Hände und Mechanik sind vollständig, die Waffen können
statt Textur die Fehlermaterial-Darstellung zeigen.

## Voll: zwei Teile zusammenfügen

Linux / macOS:

```sh
cat Gquest-0.1.30-gquest.2.apk00.part Gquest-0.1.30-gquest.2.apk01.part > Gquest.apk
sha256sum Gquest.apk    # muss 86580e22…67619f5 ergeben
adb install -r Gquest.apk
```

Windows (Eingabeaufforderung):

```bat
copy /b Gquest-0.1.30-gquest.2.apk00.part + Gquest-0.1.30-gquest.2.apk01.part Gquest.apk
certutil -hashfile Gquest.apk SHA256
```

Der Join ist geprüft: die zusammengefügte Datei ist byteweise identisch mit `Gquest.apk`
(SHA256 wie oben).

## Wenn die Installation abgelehnt wird

`INSTALL_FAILED_UPDATE_INCOMPATIBLE` oder „signatures do not match": auf dem Gerät liegt ein
anderer Signaturschlüssel. Einmal `adb uninstall -k com.gmodvr.qvrx` (behält den Content-Ordner),
dann installieren. Danach zeigt `adb shell dumpsys package com.gmodvr.qvrx | grep versionCode`
die installierte Version.
