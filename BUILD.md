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

Baut und startet die drei C++-Grenztests, die nur einen Host-Compiler und die Header
brauchen:

| Test | Prüft |
|---|---|
| `native_fingers` | alle 12 Fingerprofile, linke Hand/Wurzel/Flags unverändert, Passthrough bei ungültigem Profil |
| `vr_lua` | beide Hände, Kopf, Zielpose, Quaternion-Achsen, NaN-Gates, Action-Routing, Haptik-Clamping |
| `retired_content` | 63 ArcVR-Dateien gesichert, fremdes Addon bleibt, Wiederholung, Namenskollision, Symlink-Schutz |
| 10 Lua-Harnesses | Griff-/Mündungs-Caches, Modellpolitik, Ausrüstung, Waffenkatalog, Pose-Gate, Reload-Client, Reserve-Transfer, Performance-Sampler, Geräteprofile, Menü-Navigation |
| Rust-Unit-Tests | Startargumente, Profilparser beider Geräte, ABI-Grenzen — laufen mit, sobald `cargo` vorhanden ist |
| Geräteklassifizierung | `Quest 3S` vor `Quest 3`, Groß-/Kleinschreibung, Codename-Rückfall, Fast-Treffer, Nullzeiger |
| C++/Rust-ABI-Smoke | sechs Startfälle gegen die Release-Bibliothek, `GquestProfile`-Größe, `argv`-Eigentum |
| Android-Bridge-Cross-Compile | `aarch64-linux-android29` mit `-Wall -Wextra -Werror`; prüft die JNI-Aufrufe gegen die echten Header |
| Performance-Auswertung | `perf_report.py --test`: Urteile, Rauschgrenze, Abbruch bei gemischten Raten — synthetische Daten, keine Hardware |
| Geräteerfassung | `capture_device.py --test`: Klassifizierung, getprop-Pfad, Logcat-Zeile, Widerspruchs-Urteil — mit Stub-adb, kein Headset |
| Übersprungene Gruppen | Erscheinen als `UEBERSPRUNGEN` mit Grund und dem Zusatz „nicht geprüft" und werden am Ende zusätzlich aufgelistet; sie zählen nie als bestanden |
| Schneller Prüflauf | `build.py --units`: nur die 5 C++-Grenztests und die drei Werkzeug-Selbsttests, ohne NDK, Rust und Lua. Exit 0 = alle 4 Gruppen bestanden, Exit 1 = mindestens eine fehlgeschlagen |
| Posen-Dekodierung | `pose_snapshot`: Meter→Zoll mit Y/Z-Tausch, Gier/Nick-Achsen, nicht-finite und norm-fremde Quaternionen abgelehnt (Ergebnis bleibt unangetastet), 60 Frames aus einer Fake-Quelle mit 58 gültigen |
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

Für die 8 Harnesses wird nur die Interpreter-Bibliothek gebraucht, nicht die
game-eigene `liblua_shared.so`. Reihenfolge der Suche: `$GQUEST_LUA_LIB`, dann
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

### Ablauf

1. Basis-APK gegen Pin prüfen (`verify_gdroid_base.py`): Digest, 34 native Bibliotheken,
   vier Signaturblöcke, Finger-Blend-Aufruf, VR-Init-Patch.
2. Zehn Lua-Harnesses (Lua 5.4, siehe oben).
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
