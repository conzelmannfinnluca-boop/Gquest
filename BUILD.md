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
| 9 Lua-Harnesses | Griff-/Mündungs-Caches, Modellpolitik, Ausrüstung, Waffenkatalog, Pose-Gate, Reload-Client, Reserve-Transfer, Performance-Sampler, Menü-Navigation |

Die Lua-Harnesses laufen, sobald eine `liblua5.4` auffindbar ist; sonst meldet der
Modus `SKIPPED` (kein Fehlschlag) und bleibt bei Exit-Code 0. Der Modus meldet
ausdrücklich, welche Prüfungen **nicht** gelaufen sind und warum.

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
2. Neun Lua-Harnesses (Lua 5.4, siehe oben).
3. `cargo test`, drei C++-Grenztests, `cargo build --release`, C++/Rust-ABI-Smoke.
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
