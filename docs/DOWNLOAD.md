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
5148f8bfeead6249bc2a235a64d5ba228539e4d63ca0f12cb14b1b43267619f5  Gquest.apk (voll)
5148f8bfeead6249bc2a235a64d5ba228539e4d63ca0f12cb14b1b43267619f5  Gquest-0.1.30-gquest.2.apk (voll, gleiche Datei)
70abe8fd14918cd73bbb7985588b9604c2dd8c68a8cc6c031d299ee2846a4c37  Gquest-0.1.30-gquest.2-slim.apk
c0a3364837f9487aa12834e4486cf100145bd528c8e734c639627b2488a2eada  Gquest-0.1.30-gquest.2.apk00.part
d2082d21cc9307cfb03511d72cb8f4bb5171559dae991e191648f9f91e5fe097  Gquest-0.1.30-gquest.2.apk01.part
```

Prüfen mit `sha256sum <datei>` (Linux/macOS) oder `certutil -hashfile <datei> SHA256` (Windows).

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
sha256sum Gquest.apk    # muss 5148f8bf…67619f5 ergeben
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
