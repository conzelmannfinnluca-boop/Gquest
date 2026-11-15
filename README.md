# Gquest

Experimentelle Standalone-VR-Anpassung von Garry's Mod auf Basis von GDroid 0.1.30, entwickelt und getestet auf einer Quest 3. Quest 3S ist ein Zielgerät, wurde aber noch nicht separat getestet. Dies ist kein vollständiger 1:1-Port von GMod PCVR.

## Aktueller Stand

- Native Kopf- und Controllerbewegungen, Hände sowie bedienbares VR-Menü.
- Native HL2-Waffen mit passenden VR-Modellen und Fingerprofilen.
- Korrigierte Zweihandgriffe für SMG und Schrotflinte.
- Aktualisierte Mündungspunkte für korrekte Zielrichtung und echten Engine-Schaden.
- Brechstangenrichtung, Waffenwechsel und echter Nahkampfschaden auf der Quest bestätigt.
- Manuelles Nachladen als Standard: Magazine an der Hüfte greifen, einsetzen und durchladen.
- Waffenmechanik mit getrennter Kammer: Magazin behält seine Patronen, Einsetzen lädt nicht durch, Durchladen befördert eine geladene Patrone zurück in die Reserve, eine leere Kammer klickt, der Verschluss bleibt offen, Sicherung blockiert. Übernommen ist nur das Bedienkonzept, keine Inhalte aus H3VR ([Details und Grenzen](docs/H3VR-WAFFENMECHANIK.md)).
- Hand-Pipeline gehärtet: eine kaputte Trackingprobe hält die letzte Pose, statt die Hand verschwinden zu lassen; Geschwindigkeiten kommen aus der veröffentlichten Pose. Pistole, SMG, Schrotflinte, AR2, Magnum, Armbrust und RPG vom Träger für manuelles Nachladen und Schießen bestätigt. Für die Pistole sind zusätzlich die tatsächlichen Magazin-/Reserve-/Patronenlagerwerte protokolliert.

Die genauen Prüfungen und offenen Punkte stehen in `docs/`. Testbestätigungen gelten für die jeweils dort beschriebene Version.

## Inhalt und Build

Dieses Repository enthält den eigenen C++-/Rust-/Lua-Integrationscode und lokale Tests. Engine, Garry's-Mod-/HL2-Spieldateien, VR-Modelle, Texturen, SDKs, Videos, APKs und Signierschlüssel sind nicht enthalten.

Der bestehende Build benötigt private, separat bereitgestellte Abhängigkeiten; ein frischer Clone ist deshalb noch kein vollständiger Ein-Befehl-Build. Siehe [BUILD.md](BUILD.md) und [Integrationsdetails](Gquest-Hybrid/README.md). Der historische Ordnername `Gquest-Hybrid` bezeichnet die kleine Rust-Startkomponente mit C++-Bridge für die bestehende GDroid-Engine.

Für den Modell-Metadaten-Konverter muss `GQUEST_GAME_DIR` auf die eigene Garry's-Mod-Installation zeigen. Das Quellpaket kann keine Nutzungsrechte für Spielinhalte erteilen.

## Beiträge und Herkunft

- Laufzeitbasis: [GDroid](https://github.com/tinsarfal/GDroid), Version 0.1.30.
- VR-Modding-Referenz im Projekt: [gVRMod](https://github.com/Abyss-c0re/gVRMod).
- Spiel und HL2-Inhalte: Garry's Mod / Facepunch und Valve; separat erforderlich.
- Entwicklung mit Unterstützung des KI-Coding-Agenten OpenAI Codex.

Der eigene Integrationscode in diesem Repository steht unter der [MIT-Lizenz](LICENSE).
Die Rechte externer Projekte bleiben bei deren Urhebern: GDroid ist eine geschlossene
Binary-Abhängigkeit, Garry's-Mod-/HL2-Inhalte sind separat erforderlich, und für
übernommene VRMod-Konzepte gilt die zlib-Lizenz mit Kennzeichnungspflicht. Die
vollständige Aufstellung steht in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
