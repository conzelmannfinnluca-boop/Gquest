# H3VR-artige Waffenmechanik in GQuest

Stand: 15. November 2026

Dieses Dokument beschreibt, welche Waffenbedienung GQuest seit diesem Build hat, was davon
nachweislich geprüft ist und was nicht. Es ist **keine** Ankündigung von H3VR-Parität.

## Was diese Mechanik ist — und was nicht

H3VR (Hot Dogs, Horseshoes & Hand Grenades) ist ein kommerzielles Spiel von RUST LTD.
GQuest übernimmt **keine** Dateien, Modelle, Skripte oder Klangaufnahmen daraus, und es ist
keine 1:1-Nachbildung. Übernommen wird ausschließlich das **Bedienkonzept**, das ein
Physik-VR-Shooter braucht, um sich wie eine Waffe statt wie eine Munitionsanzeige anzufühlen:

| Konzept | Umsetzung in GQuest |
|---|---|
| Patrone im Lager (Kammer) getrennt vom Magazin | eigenes Feld `chamber`; das Magazin enthält nur, was wirklich im Magazin ist |
| Magazin behält seine Patronen | ein abgenommenes Magazin behält seinen Reststand und kann wieder eingesetzt werden |
| Magazin einsetzen lädt **nicht** durch | nach dem Einsetzen ist die Kammer leer, bis durchgeladen wird |
| Durchladen | `gquest_mech_rack`: eine Patrone wandert ins Lager; eine bereits geladene Patrone fliegt als **echte** Patrone in die Reserve |
| Sicherung | blockiert den Schuss, verbraucht nichts |
| Leerer Lauf klickt | ohne Patrone im Lager wird der Schuss blockiert, statt still aus dem Magazin zu borgen |
| Verschluss bleibt offen | bei leerem Magazin `slideLocked` |
| Trommel / Pumpe / Bolzen | eigenes Verhalten je Waffenfamilie statt einer Regel für alle |

Die harte Invariante: **Kammer + Magazin = der Wert, den die Engine als Clip führt**. Dadurch
kann diese Mechanik keine Munition erzeugen und keine verschlucken; jede Abweichung verwirft den
lokalen Zustand und liest die Engine neu.

## Waffenfamilien

| Klasse | Art | Kapazität | Zyklus | Kammer | Sicherung |
|---|---|---|---|---|---|
| `weapon_pistol` | Magazin | 18 | automatisch | ja | ja |
| `weapon_smg1` | Magazin | 45 | automatisch | ja | ja |
| `weapon_ar2` | Magazin | 30 | automatisch | ja | ja |
| `weapon_357` | Trommel | 6 | keine | nein | nein |
| `weapon_shotgun` | Schrot im Rohr | 6 | Pumpe | ja | nein |
| `weapon_crossbow` | Einzelschuss | 1 | Bolzen | ja | nein |
| `weapon_rpg` | Einzelschuss | 1 | keine | ja | ja |

Brechstange, Granate, Bugbait, Gravity Gun und Physgun haben kein Profil und werden von diesem
Modul **nicht** angefasst.

Die Kapazität stammt aus der Engine (`GetMaxClip1` bzw. `m_iMaxAmmoCount` des nativen
Magazins), nicht aus dieser Tabelle; die Tabelle ist nur der Rückfallwert für das Verhalten.
Weil die Engine-Kapazität das ganze System abdeckt, fasst eine Schrotflinte in GQuest
6 Schuss **inklusive** der Patrone im Lager, nicht 7.

## Zwei Wege in die Engine

1. **Native HLVR-Waffen** (`hlvr_weapon_*`) führen ihr Magazin als eigene Entität
   (`m_hLoadedMagazine`, `m_iCurrentAmmoCount`, `m_iMaxAmmoCount`). Geschrieben wird nur dieses
   Magazin und nur, wenn es zu dieser Waffe gehört; ein fehlgeschlagener Schreibvorgang wird
   zurückgerollt. Das Feld `m_iChamberedRounds` wird standardmäßig **nicht** geschrieben, weil
   der native Einführ-/Durchladeablauf es besitzt. Wer es trotzdem will:
   `gquest_mech_write_chamber 1` — dann wird der Schreibvorgang geprüft und bei Abweichung
   zurückgenommen.
2. **Basiswaffen** über `Clip1`/`SetClip1`, gedeckelt durch die Engine-Kapazität.

Der Schuss wird über `EntityFireBullets` gefiltert. Ruft die Engine diesen Hook für eine Waffe
nicht auf (bei nativen HLVR-Waffen möglich), passiert **nichts**: die Waffe verhält sich wie
bisher. Der Fehlerfall ist „Retail-Verhalten", nicht „Waffe tot".

## Bedienung

| Aktion | Weg |
|---|---|
| Magazin ab / an | VR-Aktion `weapon/eject` (Primärhand) oder `gquest_mech_mag` |
| Durchladen | Support-Hand nahe der Waffe nach hinten ziehen, oder `gquest_mech_rack` |
| Nachladen in einem Schritt | `gquest_mech_reload` |
| Sicherung | `gquest_mech_safety` |
| Zustand ansehen | `gquest_mech_state` (Log + Anzeige im Waffen-Panel) |
| Zustand nur für die Anzeige abfragen | `gquest_mech_poll` — schreibt keine Log-Zeile |
| Modell verwerfen und neu aus der Engine lesen | `gquest_mech_reset` |

Convars: `gquest_mech_enabled` (Standard 1), `gquest_mech_gestures` (Standard 1),
`gquest_mech_reach` (6 Einheiten), `gquest_mech_travel` (4 Einheiten),
`gquest_mech_write_chamber` (Standard 0).

Jede Zustandsänderung schreibt eine Zeile `GQUEST_MECH …` ins Log, jede Geste eine Zeile
`GQUEST_MECHGESTURE …`. Damit ist im Headset-Log ablesbar, ob die Mechanik gegriffen hat oder
ob nur die Geste nicht erkannt wurde.

## Was geprüft ist

`work/harness/test_weapon_mechanics.lua`, Teil von `build.py --tests` und `--units`:

- Aufteilung Clip → Kammer + Magazin ohne Änderung der Summe
- automatischer Zyklus kostet genau eine Patrone
- leere Kammer blockiert (auch bei Pumpe), leerer Lauf sperrt den Verschluss
- Sicherung blockiert und verbraucht nichts
- Durchladen befördert eine geladene Patrone in die **eigene Reserve** (keine Erfindung)
- abgenommenes Magazin behält seinen Reststand, Wiedereinsetzen lädt nicht durch
- frisches Magazin ist durch die Reserve gedeckelt; leere Reserve setzt nichts ein
- Trommel schießt aus der Trommel, Sicherung/Slide-Verhalten getrennt
- Rohr-Nachladen respektiert die Engine-Kapazität
- natives Magazin: nur das verknüpfte Magazin wird geschrieben, Basisfeld bleibt unberührt
- fehlgeschlagener Schreibvorgang lässt die Engine unverändert und synchronisiert neu
- ungültige native Kapazität lässt die Waffe in Ruhe
- Resync nach Engine-Änderung, und `gquest_mech_enabled 0` macht das Modul wirkungslos

## Was **nicht** geprüft ist

- **Kein Hardware-Test.** Ob `EntityFireBullets` bei den nativen HLVR-Waffen überhaupt greift,
  ob die Geste „Support-Hand nach hinten" in der Praxis auslöst und ob sich das Durchladen
  richtig anfühlt, ist **NOT TESTED**.
- Die Geometrie der Geste ist eine Heuristik (Ankerpunkt `slide`-Attachment, sonst
  Waffenursprung). Die Standardwerte sind geraten, nicht eingemessen.
- Zwei Schreiber auf denselben Zustand sind möglich, wenn die Engine den Clip selbst
  weiterzählt. Der Resync fängt das ab, aber er ist ein Sicherheitsnetz, kein Beweis.
- Es gibt keine H3VR-Modelle, keine H3VR-Sounds, keine H3VR-Mechanikdateien in diesem Paket.

## Referenzen

Die Videos und das Workshop-Addon aus der Anforderung dienen nur als **Verhaltensbeschreibung**
(Zielbild). Sie wurden nicht heruntergeladen, nicht ausgelesen und ihr Inhalt ist nicht in diesem
Repository oder im APK enthalten. Rechte an H3VR liegen bei RUST LTD, Rechte an Addons bei deren
Autoren.
