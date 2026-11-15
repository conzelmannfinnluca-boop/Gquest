# Build

Es gibt drei Einstiege. Der erste funktioniert **ohne** jede private Datei und ist
deshalb der, den man nach einem frischen Clone zuerst ausführt.

## 1. Voraussetzungen prüfen (immer möglich)

```sh
python3 Gquest-Hybrid/tools/build.py --check
```

Listet jede Voraussetzung des vollen Builds mit Pfad, Zweck und Beschaffungsweg.
Fehlt etwas, endet der Befehl mit Exit-Code 1 — ohne Traceback. Zusätzlich prüft er,
dass die gespiegelten Bridge-Dateien in `work/` und `Gquest-Hybrid/bridge/` byte-identisch
sind. Weichen sie ab, ist die getestete nicht mehr die ausgelieferte Fassung.

Zwei getrennte Abschnitte, weil sie unterschiedlich viel bedeuten:

| Abschnitt | Fehlt etwas |
|---|---|
| **Build-Voraussetzungen** (9) | Der volle Build ist nicht möglich; Exit-Code 1. |
| **Test-Voraussetzungen** (4: `c++`, `cargo`, Bridge-Cross-Compiler, Lua 5.4) | Nur die betroffene Gruppe erscheint als `UEBERSPRUNGEN`; der Build bleibt möglich, der Exit-Code ändert sich nicht. |

Beide werden mit derselben Auflösung geprüft, die auch die Läufe verwenden: `cargo`
zählt auch aus dem `PATH`, der Cross-Compiler auch als gestagter `clang`
(`stage_ndk.py`), Lua auch aus dem System. Sonst meldet `--check` Dinge als fehlend, die
der Build sehr wohl findet.

## 2. Grenztests (ohne private Daten)

```sh
python3 Gquest-Hybrid/tools/build.py --tests
```

Baut und startet die C++-Grenztests, die nur einen Host-Compiler und die Header brauchen:

| Test | Prüft |
|---|---|
| `native_fingers` | alle 12 Fingerprofile, linke Hand/Wurzel/Flags unverändert, Passthrough bei ungültigem Profil |
| `vr_lua` | beide Hände, Kopf, Zielpose, Quaternion-Achsen, NaN-Gates, Action-Routing, Haptik-Clamping |
| `retired_content` | 63 ArcVR-Dateien gesichert, fremdes Addon bleibt, Wiederholung, Namenskollision, Symlink-Schutz |
| 12 Lua-Harnesses | Griff-/Mündungs-Caches, Modellpolitik, Ausrüstung, Waffenkatalog, Pose-Gate, Reload-Client, Reserve-Transfer, Performance-Sampler, Geräteprofile (inkl. Komfort-Schlüssel), Menü-Navigation (inkl. Playspace- und Glättungs-Knöpfe sowie inhaltsgesteuerter Rahmenhöhe), Playspace, Handposen-Glättung |
| Rust-Unit-Tests | Startargumente, Profilparser beider Geräte, ABI-Grenzen — laufen mit, sobald `cargo` vorhanden ist |
| Geräteklassifizierung | `Quest 3S` vor `Quest 3`, Groß-/Kleinschreibung, Codename-Rückfall, Fast-Treffer, Nullzeiger |
| C++/Rust-ABI-Smoke | sechs Startfälle gegen die Release-Bibliothek, `GquestProfile`-Größe, `argv`-Eigentum |
| Android-Bridge-Cross-Compile | `aarch64-linux-android29` mit `-Wall -Wextra -Werror`; prüft die JNI-Aufrufe gegen die echten Header |
| Performance-Auswertung | `perf_report.py --test`: Urteile, Rauschgrenze, Abbruch bei gemischten Raten — synthetische Daten, keine Hardware |
| Geräteerfassung | `capture_device.py --test`: Klassifizierung, getprop-Pfad, Logcat-Zeile, Widerspruchs-Urteil — mit Stub-adb, kein Headset |
| Übersprungene Gruppen | Erscheinen als `UEBERSPRUNGEN` mit Grund und dem Zusatz „nicht geprüft" und werden am Ende zusätzlich aufgelistet; sie zählen nie als bestanden |
| Schneller Prüflauf | `build.py --units`: nur die C++-Grenztests und die fünf Werkzeug-Selbsttests, ohne NDK, Rust und Lua. Exit 0 = alle 6 Gruppen bestanden, Exit 1 = mindestens eine fehlgeschlagen |
| Playspace (Lua) | `test_playspace.lua`: Snap-Turn 30° in beide Richtungen, Pitch/Roll bleiben, eigener Schritt, Wrap über beide Nahtstellen, ungültige Richtungen/Schritte/Typen und fehlender Spieler abgelehnt, View unverändert |
| Fake-Host (G2) | `fake_host`: 60 Frames mit Snap-Turn, Recenter und Sitzend mitten im Lauf, kaputte Köpfe und fehlende Frames abgelehnt und geloggt, Hände einzeln verworfen, gültige und abgelehnte Haptik; Content-Installation wird vor dem Schreiben beurteilt, ist per Größe idempotent, `lua/` wird immer neu geschrieben, der erste schlechte Eintrag stoppt den Lauf. Zweiter Lauf unter schlechten Bedingungen: Jitter, verlorenes Sample, eingefrorene und rückwärts laufende Uhr, Zehn-Sekunden-Sprung mit 20-ms-Schritt danach (pinnt den Resync), Drei-Sekunden-Stall (geklemmt) und NaN-Zeitstempel. Ohne Engine |
| Plattform-Interfaces | `platform`: Frame-Delta geklemmt und gegen rückwärts laufende oder nicht-finite Werte abgelehnt, Log-Stufen geordnet, Asset-Pfade genau dort abgelehnt, wo der Content-Installer sie ablehnt, zu große und fehlende Reads lassen den Puffer unangetastet, Haptik-Grenzen, Frame-Step veröffentlicht Kopf und Hände oder nichts. Übersetzt ohne Engine-Header (Gate G1) |
| Playspace | `playspace`: Snap-Turn-Schritte inkl. Wrap über ±180, ungültige Richtungen/Schritte abgelehnt, Smooth-Turn pro Frame begrenzt, Recenter setzt Kopf für jeden Steuerkurs auf die Achse (Höhe bleibt), Sitzend/Stehend-Versatz angewendet und zurückgenommen |
| Posen-Dekodierung | `pose_snapshot`: Meter→Zoll mit Y/Z-Tausch, Gier/Nick-Achsen, nicht-finite und norm-fremde Quaternionen abgelehnt (Ergebnis bleibt unangetastet), 60 Frames aus einer Fake-Quelle mit 58 gültigen |
| Frame-Zeit-Politik | `frame_policy.py --test`: prüft zuerst den Scanner selbst (rohe Frame-Zeit in Waffen-/Handcode wird gefunden, ein Kommentar nicht, der Perf-Sampler ist erlaubt) und scannt dann den echten Lua-Baum. Grund: die Handposen-Glättung nimmt ihren Schritt aus `gquest_frame_time.lua`, und wer eine weitere Glättung schreibt, darf nicht `FrameTime()` integrieren |
| Handposen-Glättung | `test_hand_smoothing.lua`: Frame-Schritt (Start, Messung, wiederholte/kaputte Lesung, 0,5-s-Klemmung) und Glättung (erster Sample snappt, 36 Hz = 72 Hz, ohne Schritt gehalten, Teleport snappt, kurzer Weg über die Naht, getrennter Zustand je Hand, Stufen Aus/Mild/Stark und Ablehnung unbekannter Namen) |
| Gepinnte Adressen | `pinned_addresses.py --test`: Bridge-Offsets gegen den Audit-Datensatz, ELF-Programmheader-Leser an synthetischen Headern, Code/Daten-Klassifizierung. Ohne `libclient.so` bleibt die Segmentzugehörigkeit offen (Exit 2 im Normalauf) |
| Lesbarer Speicher | `readable_memory`: gemappte Seite, letztes Byte, `PROT_NONE`, Bereich über eine Mapping-Grenze, Nullzeiger, überlaufende Länge und Länge 0 mit `mmap`/`mprotect` geprüft |
| Content-Installation | `content_install`: Manifest wird bei absolutem Pfad, `..`, leerem Pfad, nicht-numerischer/überlaufender Größe und CRLF abgelehnt; `mkdir -p` idempotent und steigt nicht in eine Datei hinab |
| Geräte-JNI | `device_jni`: Mock-JNI prüft Aufrufkette, `GET_META_DATA`-Flag, Fehlerpfade (fehlender Schlüssel, leeres Bundle, werfende Aufrufe) und dass jede lokale Referenz freigegeben wird. Das echte `PackageManager`-Verhalten bleibt ungeprüft |
| Überlagerungs-Manifest | `overlay_manifest.py --test`: Wert zurücklesen, zusammenführen, Duplikate und unbekannte IDs ablehnen — synthetische Manifeste, keine APK |

### NDK für den Bridge-Check

Der Testmodus kompiliert `bridge/quest_engine_bridge.cpp` für aarch64, damit die
JNI-Aufrufe typgeprüft sind. Dafür genügen clang und die Sysroot-Header — kein SDK:

```sh
python3 Gquest-Hybrid/tools/stage_ndk.py          # lädt das NDK-Zip, legt ~190 MB ab
python3 Gquest-Hybrid/tools/stage_ndk.py --check  # Stand prüfen
```

Liegt ein vollständiger NDK an `work/android-sdk/ndk/23.2.8568313`, wird der bevorzugt.
Das Linken von `liblauncheq.so` braucht weiterhin Basis-APK und JDK und gehört zum
Gesamtbuild, nicht zum Testmodus.

Die Lua-Harnesses laufen, sobald eine `liblua5.4` auffindbar ist; sonst meldet der
Modus `SKIPPED` (kein Fehlschlag) und bleibt bei Exit-Code 0. Der Modus meldet
ausdrücklich, welche Prüfungen **nicht** gelaufen sind und warum.

### Rust-Toolchain bereitstellen

Die Rust-Tests laufen automatisch mit, wenn `work/toolchains/cargo/bin/cargo` oder ein
System-`cargo` vorhanden ist; sonst meldet der Modus `SKIPPED`.

```sh
export RUSTUP_HOME="$PWD/work/toolchains/rustup" CARGO_HOME="$PWD/work/toolchains/cargo"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
  | sh -s -- -y --profile minimal --default-toolchain stable --no-modify-path
```

`work/toolchains/` ist in `.gitignore`; die Toolchain wird pro Umgebung neu installiert.
Für den Android-Cross-Build wird zusätzlich das Target `aarch64-linux-android` gebraucht.

### Lua 5.4 bereitstellen

Für die Harnesses wird nur die Interpreter-Bibliothek gebraucht, nicht die game-eigene
`liblua_shared.so`. Reihenfolge der Suche: `$GQUEST_LUA_LIB`, dann
`work/toolchains/lua/lib/liblua5.4.so.0`, dann das System.

```sh
mkdir -p work/toolchains/lua && cd work/toolchains/lua
curl -O https://www.lua.org/ftp/lua-5.4.7.tar.gz
tar xzf lua-5.4.7.tar.gz && cd lua-5.4.7
make linux MYCFLAGS=-fPIC
cd src && mkdir -p ../../lib \
  && gcc -shared -fPIC -o ../../lib/liblua5.4.so.0 \
     $(ls *.o | grep -vE '^(lua|luac)\.o$') -lm
```

Wichtig: `lua.o` und `luac.o` müssen ausgeschlossen werden — beide definieren `main`
und brechen sonst das Linken der Shared Library. `work/toolchains/` ist in
`.gitignore`; die Bibliothek wird pro Umgebung neu gebaut.

## 3. Voller Build (braucht alle privaten Abhängigkeiten)

```sh
python3 Gquest-Hybrid/tools/build.py
```

Setzt voraus:

| Datei / Ordner | Zweck |
|---|---|
| `outputs/GDroid-0.1.30.apk` | gepinnte offizielle Basis, SHA256 `28bcce6d…` |
| `work/gdroid-0.1.30-native/` | entpackte native Bibliotheken dieser APK |
| `work/android-sdk/ndk/23.2.8568313/` | Cross-Compiler `aarch64-linux-android29-clang++` |
| `work/android-sdk/build-tools/34.0.0/` | `zipalign`, `apksigner` |
| `work/toolchains/jdk/` | JDK für `apksigner` |
| `work/toolchains/cargo/` | Rust-Toolchain (ein System-`cargo` wird als Fallback genutzt) |
| `work/quest-vr-content/` + `work/quest-vr-content-manifest.json` | privater VR-Content |
| `~/.android/debug.keystore` | Debug-Signatur |
| `GQUEST_GAME_DIR` | nur für den Modell-Metadaten-Konverter |

Diese Dateien sind bewusst **nicht** Bestandteil des Repositories: Fremd-APK, SDKs,
Spielinhalte, Signaturschlüssel. `.gitignore` schließt ihre Endungen aus.

### Einrichtung auf einem frischen Rechner

Reihenfolge zählt: `sdkmanager` ist ein Java-Programm, also muss das JDK vor dem SDK da
sein. Alle Pfade sind relativ zum Repository-Wurzelverzeichnis (eine Ebene über
`Gquest-Hybrid/`), weil `build.py` sie so auflöst. Ziel der Einrichtung ist
`python3 Gquest-Hybrid/tools/build.py --check` mit **Exit-Code 0**.

**1. Basis-APK** (nicht aus Quellen baubar, Upstream veröffentlicht nur Binärdateien):

```sh
mkdir -p outputs
# Release 0.1.30 von github.com/tinsarfal/GDroid nach outputs/GDroid-0.1.30.apk
sha256sum outputs/GDroid-0.1.30.apk
# muss 28bcce6d656f324b883fa638ceae2893cfa875e423f28a7fbc2329c5cdd5d13c sein
```

Stimmt der Digest nicht, bricht `verify_gdroid_base.py` ab — jede andere Fassung hat
andere Offsets und der gepatchte VR-Init landet im Nichts.

**2. Native Bibliotheken flach entpacken** (34 `.so`, `-j` damit keine `lib/`-Ebenen
entstehen):

```sh
mkdir -p work/gdroid-0.1.30-native
unzip -o -j outputs/GDroid-0.1.30.apk 'lib/arm64-v8a/*.so' -d work/gdroid-0.1.30-native
ls work/gdroid-0.1.30-native | wc -l   # 34
```

Die Dateinamen müssen zu `native_sha256` in `work/gdroid-0.1.30-build-pin.json` passen;
genau diese Liste prüft der Basis-Test gegen die im Paket liegenden Bibliotheken.

**3. JDK 17** nach `work/toolchains/jdk` (erwartet wird `work/toolchains/jdk/bin/java`):

```sh
mkdir -p work/toolchains && cd work/toolchains
curl -L -o jdk.tar.gz "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse"
tar xzf jdk.tar.gz && mv jdk-17* jdk && rm jdk.tar.gz
cd ../.. && work/toolchains/jdk/bin/java -version
```

**4. Android SDK: build-tools 34.0.0 und NDK 23.2.8568313** nach `work/android-sdk`:

```sh
cd work
# Build-Nummer in der URL ggf. auf die aktuelle aus developer.android.com/studio tauschen
curl -LO https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip -q commandlinetools-linux-11076708_latest.zip -d cmdline-tools-tmp
mkdir -p android-sdk-cmdline/cmdline-tools
mv cmdline-tools-tmp/cmdline-tools android-sdk-cmdline/cmdline-tools/latest
SDKM=android-sdk-cmdline/cmdline-tools/latest/bin/sdkmanager
yes | $SDKM --sdk_root="$PWD/android-sdk" --licenses > /dev/null
$SDKM --sdk_root="$PWD/android-sdk" 'build-tools;34.0.0' 'ndk;23.2.8568313'
cd ..
ls work/android-sdk/build-tools/34.0.0/zipalign \
   work/android-sdk/build-tools/34.0.0/lib/apksigner.jar \
   work/android-sdk/ndk/23.2.8568313/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android29-clang++
```

Die NDK-Version ist gepinnt: `build.py` linkt mit genau diesem Pfad, ein anderes NDK wird
nicht gefunden. `sdkmanager` braucht das JDK aus Schritt 3 im `PATH`:
`export PATH="$PWD/work/toolchains/jdk/bin:$PATH"`.

**5. Rust mit Android-Target:**

```sh
export RUSTUP_HOME="$PWD/work/toolchains/rustup" CARGO_HOME="$PWD/work/toolchains/cargo"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
  | sh -s -- -y --profile minimal --default-toolchain stable --no-modify-path
$CARGO_HOME/bin/rustup target add aarch64-linux-android
```

Ein System-`cargo` wird als Fallback genutzt; ohne das Android-Target scheitert aber Schritt 4
des Ablaufs (`cargo build --target aarch64-linux-android`).

**6. Debug-Schlüssel:**

```sh
mkdir -p ~/.android
work/toolchains/jdk/bin/keytool -genkeypair -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -storepass android -keypass android \
  -keyalg RSA -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
```

`build.py` signiert mit `--ks-pass pass:android --key-pass pass:android`; ein Schlüssel mit
anderem Passwort bricht die Signierung ab.

**7. Privater VR-Content** — `work/quest-vr-content/` (Dateibaum) und
`work/quest-vr-content-manifest.json`:

```json
{
  "files": [
    {
      "path": "maps/d1_trainstation_01.bsp",
      "bytes": 12345678,
      "sha256": "<64 Hexzeichen>"
    }
  ]
}
```

`path` ist relativ zu `work/quest-vr-content/`, ohne führenden `/`, ohne `..`, ohne Tabs
oder Zeilenumbrüche. **`bytes` und `sha256` werden beim Bauen gegen die echte Datei geprüft**
und müssen stimmen, sonst bricht `build_quest_lab.py` ab. Erzeugen lässt sich beides mit:

```sh
python3 - <<'PY'
import hashlib, json
from pathlib import Path
root = Path("work/quest-vr-content")
files = []
for f in sorted(p for p in root.rglob("*") if p.is_file()):
    data = f.read_bytes()
    files.append({"path": f.relative_to(root).as_posix(), "bytes": len(data),
                  "sha256": hashlib.sha256(data).hexdigest()})
Path("work/quest-vr-content-manifest.json").write_text(json.dumps({"files": files}, indent=2) + "\n")
print(len(files), "Dateien")
PY
```

Nach Schritt 7 muss `--check` sauber sein; erst dann lohnt der volle Build:

```sh
python3 Gquest-Hybrid/tools/build.py --check && echo "alle Voraussetzungen vorhanden"
```

Meldet er weiterhin etwas, nennt er Pfad, Zweck und Beschaffungsweg — dieselbe Liste, die
oben abgearbeitet wird. `--check` prüft zusätzlich, dass `work/` und `Gquest-Hybrid/bridge/`
byte-identisch sind; weichen sie ab, ist die getestete nicht mehr die ausgelieferte Fassung.

**8. Eigenes Lua** muss nicht eingerichtet werden: `work/gquest-ui/` liegt im Repository und
wird beim Paketieren mitgenommen. Der optionale Konverter für Waffenmodell-Metadaten
(`work/prepare_weapon_model_overrides.py`) braucht zusätzlich `GQUEST_GAME_DIR`.

### Ablauf

1. Basis-APK gegen Pin prüfen (`verify_gdroid_base.py`): Digest, 34 native Bibliotheken,
   vier Signaturblöcke, Finger-Blend-Aufruf, VR-Init-Patch. Das läuft **vor** allem anderen,
   damit ein falscher Basispaket-Stand nicht erst nach Minuten Cross-Build auffällt.
2. Zwölf Lua-Harnesses (Lua 5.4, siehe oben), darunter der Menü-Harness.
3. `cargo test`, vier C++-Grenztests, `cargo build --release`, C++/Rust-ABI-Smoke.
4. Cross-Build `liblauncheq.so` gegen NDK und `liblauncher.so` des Basispakets.
5. Overlay-APK bauen (`build_quest_lab.py`), `zipalign`, signieren, verifizieren.
6. Payload-Identität: nur `AndroidManifest.xml`, `classes.dex` und
   `lib/arm64-v8a/libclient.so` dürfen sich gegenüber der Basis ändern.

Ergebnis: `Gquest-Hybrid/dist/Gquest-Rust-GDroid.apk` + `verification.json`.

## Hilfsskripte

| Skript | Zweck |
|---|---|
| `Gquest-Hybrid/tools/cargo.py` | cargo mit privater oder System-Toolchain, klare Fehlermeldung wenn keine da ist |
| `work/package_gdroid_source.py` | Quellarchiv des eigenen Codes erneut erstellen |
| `work/run_lua_checks.py` | Lua-Harnesses über System-Lua 5.4 ausführen |
| `work/prepare_weapon_model_overrides.py` | Waffenmodell-Metadaten, braucht `GQUEST_GAME_DIR` |

## Bekannte Einschränkung

Ohne die privaten Abhängigkeiten ist **kein** APK baubar. Das ist eine
Lizenz-/Rechteentscheidung, kein Defekt: Fremd-APK und Retail-Inhalte dürfen nicht
weitergegeben werden. Der Build ist deshalb reproduzierbar **gegeben die Eingaben**,
nicht aus dem Repository allein.
