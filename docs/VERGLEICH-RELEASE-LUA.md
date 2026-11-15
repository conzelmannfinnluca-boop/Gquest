# Vergleich: Lua aus dem Release `test-von-Gqeust` gegen den aktuellen Stand

Anlass: Das Release-APK (`versionCode 74`, `0.1.30`, 283 MB) enthielt 11 Lua-Dateien. Geprüft
wurde Zeile für Zeile, ob darin Hand- oder UI-Logik steckt, die im neueren Overlay (18 Dateien,
`0.1.30-gquest.2`) verloren gegangen ist. Ergebnis vorweg: **nichts fehlt** — sechs Dateien sind
byteweise identisch, fünf sind vollständige Obermengen. Keine Funktion, kein Konsolenbefehl und
kein Hook existiert nur im Release.

Vorgehen: `diff -u` pro Datei, dazu ein Abgleich aller `function`-, `concommand.Add`- und
`hook.Add`-Namen beider Seiten.

## Die elf Dateien

| Datei | Release | aktuell | Befund |
|---|---|---|---|
| `client/gquest_00_vr_api.lua` | gleich | gleich | **byteweise identisch** |
| `client/gquest_01_weapon_policy.lua` | gleich | gleich | **byteweise identisch** |
| `client/gquest_native_weapon_pose.lua` | gleich | gleich | **byteweise identisch** |
| `client/gquest_weapon_align.lua` | gleich | gleich | **byteweise identisch** |
| `client/gquest_weapon_models.lua` | gleich | gleich | **byteweise identisch** |
| `server/gquest_hl2_models.lua` | gleich | gleich | **byteweise identisch** |
| `client/gquest_reload.lua` | 2.657 B | 3.929 B | Obermenge, +43 / −11 Zeilen |
| `server/gquest_hl2_equipment.lua` | 3.777 B | 7.332 B | Obermenge, +62 / −1 Zeilen |
| `client/gquest_wrist_hud.lua` | 2.384 B | 9.324 B | Obermenge, +181 / −30 Zeilen |
| `client/gquest_weapon_catalog.lua` | 2.354 B | 10.303 B | Obermenge, +159 / −2 Zeilen |
| `client/gquest_vr_ui.lua` | 11.279 B | 21.260 B | Obermenge, +225 / −50 Zeilen |

## Was in den fünf geänderten Dateien ersetzt wurde

Jede Zeile, die es nur im Release gibt, ist unten erklärt. Es sind ausschließlich Umbauten, keine
entfernten Funktionen.

### `gquest_wrist_hud.lua` (Hand)

| Release-Zeilen | heute |
|---|---|
| `local rotation=Angle(...)`; `forward`/`up` rotieren und `Vector(x,-z,y)` tauschen | liegt jetzt in `sourcePoseAngle()` (Zeilen 56–66), identische Umrechnung, zusätzlich auf endliche Werte geprüft |
| `result[...]={pos=headWorld+delta,ang=worldAngle}` direkt | geht durch `publish(hand, pos, angle, step, usable)`: hält bei NaN die letzte Pose, statt eine kaputte zu veröffentlichen, und liefert `vel`/`angvel` |
| `hook.Remove("PostDrawTranslucentRenderables","GquestWristHUD")`, `hook.Remove("HUDPaint","GquestVitals")`, `gquest_wrist_hud=0` | unverändert vorhanden (Zeilen 198–201) |

Zusätzlich neu: `GquestXR.DescribeHands`, `GquestXR.ResetHand`, `gquest_hands_state`,
`readable`/`readableAngle`, `frameStep`, `wrapDelta` — die Diagnose, mit der ein Gerätelauf die
Hand prüfbar macht.

### `gquest_reload.lua`

| Release | heute |
|---|---|
| `releaseAt=RealTime()+0.18` direkt im Request, `refillAt` danach | `request()` → `release()`/`refill()` mit `pendingWeapon`: bricht ab, wenn die Waffe vorher gewechselt wird (`GQUEST_RELOAD cancelled: …`) |
| `if assisted:GetBool()` | `assistedEnabled()`, zusätzlich an zwei ConVars gebunden (`gquest_reload_assisted`, `gquest_reload_physical`) |
| `chat.AddText("HL2: Magazin ausgeworfen; Munition kommt aus dem eigenen Vorrat.")` | `chat.AddText("Magazin auswerfen, links an der Huefte ein neues greifen, einsetzen und durchladen.")` — Hinweis auf die manuelle Bedienung statt auf die Unterstützung |
| `GquestReload.Request`, `concommand.Add("gquest_reload", …)`, `hook.Add("ShutDown", …)`, `GQUEST_RELOAD requested=…` | alle vorhanden; der ShutDown-Hook räumt zusätzlich `pendingWeapon` ab |

### `gquest_hl2_equipment.lua`

| Release | heute |
|---|---|
| `print("GQUEST_RELOAD_REFILL "..refill(player))` | `print("GQUEST_RELOAD_REFILL "..message)`, nachdem `refill()` sein Ergebnis prüft; die Log-Zeile bleibt wortgleich |

### `gquest_weapon_catalog.lua`

| Release | heute |
|---|---|
| `close:DoClick=function() frame:Close();gui.HideGameUI() end` | `closePanel` (gleiche zwei Aufrufe, jetzt an einer Stelle) |
| `frame:Close();gui.HideGameUI()` direkt beim Waffenklick | Klick quittiert erst `wird ausgeruestet ...`, schließt dann über `closePanel` |

### `gquest_vr_ui.lua`

Der komplette Release-Aufbau (eine Spalte, feste `1032x1104`-Stufen, Profil direkt in der Datei
gelesen/geschrieben, `panel:Help`) ist ersetzt durch zwei Spalten plus das Profilmodul
`gquest_vr_profiles.lua` (Geräte `quest3`/`quest3s`, je eigene Stufen). Alle Release-Bedienelemente
haben ein Gegenstück: Bildprofil, Randauflösung, Bildwiederholrate, „Waffenmodelle prüfen",
„Waffe ausrichten", Zurücksetzen (heute „Empfohlen fuer <Gerät> wiederherstellen").

## Nicht übernommen — und warum

- **Der Lua-Stand des Releases selbst.** Er ist älter: `gquest_weapon_catalog.lua` 2.354 statt
  10.303 Bytes, ohne Mechanik-Knöpfe, ohne Live-Zeile, ohne Lesezeit; `gquest_vr_ui.lua` ohne
  Zwei-Spalten-Layout und ohne Geräteprofile. Ein Zurückkopieren würde funktionierende Teile
  entfernen.
- **Module, die es nur bei uns gibt** (7 Dateien): `gquest_weapon_mechanics.lua`,
  `gquest_mech_gestures.lua`, `gquest_playspace.lua`, `gquest_vr_profiles.lua`,
  `gquest_hand_smoothing.lua`, `gquest_frame_time.lua`, `gquest_perf_hud.lua`.
- **Der Content des Releases** (218 Modelle, 128 Materialien, 12 Scripts) — der ist übernommen,
  byteweise, siehe `docs/RELEASE_NOTES_v0.1.30-gquest.md`.

## Grenzen dieser Prüfung

Der Vergleich ist statisch: gleiche Funktionen, gleiche Hooks, gleiche Log-Zeilen. Ob die
Handpose auf dem Gerät richtig aussieht, sagt er nicht — dafür braucht es `GQUEST_HANDS …` aus
einem echten Lauf.
