# Gquest

Experimentelle Standalone-VR-Anpassung von Garry's Mod auf Basis von GDroid 0.1.30, entwickelt und getestet auf einer Quest 3. Quest 3S ist ein Zielgerät, wurde aber noch nicht separat getestet. Dies ist kein vollständiger 1:1-Port von GMod PCVR.

## Aktueller Stand

- Native Kopf- und Controllerbewegungen, Hände sowie bedienbares VR-Menü.
- Native HL2-Waffen mit passenden VR-Modellen und Fingerprofilen.
- Korrigierte Zweihandgriffe für SMG und Schrotflinte.
- Aktualisierte Mündungspunkte für korrekte Zielrichtung und echten Engine-Schaden.
- Brechstangenrichtung, Waffenwechsel und echter Nahkampfschaden auf der Quest bestätigt.
- Manuelles Nachladen als Standard: Magazine an der Hüfte greifen, einsetzen und durchladen. Pistole mit tatsächlichen Magazin-/Reserve-/Patronenlagerwerten geprüft; SMG und Schrotflinte vom Träger bestätigt. Weitere Waffenfamilien bleiben einzeln zu prüfen.

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

Die Rechte externer Projekte bleiben bei deren Urhebern. Für den eigenen Integrationscode wurde noch keine Veröffentlichungs-/Weiterverwendungslizenz festgelegt; es wird hier keine Lizenz fremder Komponenten ersetzt.
