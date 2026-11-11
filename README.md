# SchoolPresence

Digitale Schul- und Anwesenheitsverwaltung für die fiktive Entwicklungsinstanz „Schule an der Ruhraue“. Die Oberfläche folgt den Designreferenzen aus der Bauanleitung: marineblaue Navigation, klare Karten, Kennzahlen und eine farblich und textlich ausgezeichnete Anwesenheitsliste.

## Aktueller Stand

Enthalten sind die responsive Weboberfläche, serverseitige Anmeldung und Rollenprüfung, SQLite-Datenspeicherung, Klassen- und Schüleranlage, Anwesenheitssitzungen samt offener und abgeschlossener Listen, Änderungsprotokoll, rollenbeschränkte CSV-Berichte, Statistiken auf Basis gespeicherter Daten, Schulprofil und Benutzerverwaltung. Beispieldaten sind fiktiv.

Einige Menüpunkte sind bereits als verständliche Oberfläche vorhanden, ihre Verwaltungsabläufe sind noch nicht implementiert: Entschuldigungsbearbeitung, Stundenplanänderungen und Konfliktprüfung, Vertretungsspeicherung und interne Benachrichtigungen. Auch Passwortänderung/-zurücksetzung, kontoverwaltete Rollenberechtigungen, Aufbewahrungs- und Löschläufe sowie automatisierte Tests fehlen. Die Anwendung ist ein Entwicklungsstand und noch nicht für echte Schülerdaten oder den produktiven Schuleinsatz freigegeben.

## Lokal starten

Voraussetzung: Node.js 20 oder neuer.

```sh
npm install
cp .env.example .env
# SESSION_SECRET in .env durch einen langen, zufälligen Wert ersetzen
npm run build
npm start
```

Dann `http://localhost:3000` öffnen. Für die Frontend-Entwicklung in einem Terminal `npm start` und in einem zweiten `npm run dev` ausführen; Vite läuft unter `http://localhost:5173`.

## Fiktive Demo-Zugänge

Alle drei Rollen verwenden ausschließlich für die lokale Erstinstallation dasselbe temporäre Demo-Passwort `Schule2026!`:

| Rolle | E-Mail |
| --- | --- |
| Administrator | `admin@schoolpresence.local` |
| Schulleitung | `leitung@schoolpresence.local` |
| Lehrkraft | `mara@schoolpresence.local` |

Die SQLite-Datenbank entsteht beim ersten Serverstart in `data/schoolpresence.sqlite`. Zum Zurücksetzen der Beispieldaten Server beenden und diese lokale Datei löschen.

## Datenmodell

Das SQLite-Schema wird beim Serverstart in `server.js` angelegt und enthält Schulen, Benutzer, Klassen, Schüler, Fächer, Anwesenheitssitzungen, Anwesenheitseinträge, Benachrichtigungen und Audit-Logs. Fremdschlüssel, eindeutige Sitzungs- und Schülerkombinationen, Statusprüfungen und Transaktionen schützen kritische Anwesenheitsschreibvorgänge. `school_id` grenzt Abfragen schulbezogen ein. Die Schultabellen werden aktuell als Schema zur späteren Mehrschulerweiterung genutzt; ein automatisierter Migrationen-Workflow fehlt noch.

## Betrieb und Veröffentlichung

Für einen Serverbetrieb müssen mindestens ein zufälliges `SESSION_SECRET`, HTTPS, ein dauerhaftes beschränktes Datenvolume für `DATA_DIR`, Backups und getestete Wiederherstellung eingerichtet werden. In Produktion sollte ein dauerhafter Session-Store statt des Express-Memory-Stores konfiguriert und das Admin-Demopasswort nach dem initialen Setup geändert werden. Setze `NODE_ENV=production` hinter einem vertrauenswürdigen HTTPS-Proxy; sichere Cookies werden dann vorausgesetzt. Lege `.env` und den Datenordner niemals in GitHub ab.

GitHub Pages kann diese Anwendung nicht ausführen, da die API einen Node-Server und eine dauerhafte SQLite-Datei benötigt. Ein GitHub-Repository kann den Quellcode aufnehmen; für eine öffentliche lauffähige Website ist zusätzlich ein Node-fähiger Hoster mit persistentem Speicher erforderlich. Vor echtem Schulbetrieb sind Hosting, Datenschutz, Rechtsgrundlage, Rollen, Auftragsverarbeitung und Aufbewahrung durch die Schule freizugeben.
