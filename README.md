# SchoolPresence

Responsive digitale Schul- und Anwesenheitsverwaltung für die fiktive Entwicklungsinstanz „Schule an der Ruhraue“. Das Frontend wird als statische Vite-App ausgeliefert; Supabase stellt PostgreSQL, Auth und abgesicherte Datenzugriffe bereit.

## Supabase-Projekt einrichten

1. Im SQL Editor des Projekts `bqoxpwerrrsrfdvpelnh` den Inhalt aus `supabase/migrations/202611110001_schoolpresence.sql` einmal vollständig ausführen. Dadurch werden Tabellen, Indizes, Berechtigungsfunktionen, RLS-Regeln und ausschließlich fiktive Klassen-/Schülerdaten angelegt.
2. In **Authentication → Users** einen ersten Admin-Benutzer anlegen.
3. Im SQL Editor den letzten Setup-Block aus der Migration mit der Admin-E-Mail ausführen, indem `YOUR-ADMIN-EMAIL` ersetzt wird. Er verknüpft das Auth-Konto mit der Schule und Rolle `admin`.
4. In **Settings → API Keys** den **Publishable Key** ablesen. Nur dieser öffentliche Schlüssel kommt in die Browser-App. Einen `sb_secret_…`-Key niemals veröffentlichen oder in Browser-Konfiguration bzw. GitHub-Quellcode eintragen.
5. Für lokale Nutzung `.env.example` nach `.env` kopieren und die Projekt-URL sowie den Publishable Key eintragen.

Die Supabase-URL des verknüpften Projekts lautet `https://bqoxpwerrrsrfdvpelnh.supabase.co`.

## Lokal starten

Voraussetzung: Node.js 20 oder neuer.

```sh
npm install
cp .env.example .env
# VITE_SUPABASE_PUBLISHABLE_KEY in .env ergänzen
npm run dev
```

Vite zeigt danach die lokale URL an. Für einen produktionsnahen lokalen Build `npm run build` und anschließend `npm run preview` verwenden.

## GitHub Pages

Das Repository enthält einen Actions-Workflow unter `.github/workflows/deploy-pages.yml`. In den GitHub-Repository-Einstellungen unter **Secrets and variables → Actions** müssen diese Repository-Secrets gesetzt sein:

- `VITE_SUPABASE_URL` = `https://bqoxpwerrrsrfdvpelnh.supabase.co`
- `VITE_SUPABASE_PUBLISHABLE_KEY` = Publishable Key aus Supabase

Danach bei **Settings → Pages** die Bereitstellung über **GitHub Actions** aktivieren. Jeder Push auf `main` baut und veröffentlicht das Frontend. Der Publishable Key ist dafür vorgesehen, im Browser aufzutauchen; Row Level Security schützt die Daten. Der Secret Key darf nicht als Vite-Variable oder GitHub-Pages-Secret in den Frontend-Build gelangen.

## Benutzerverwaltung

Öffentliche Registrierung ist deaktiviert. Der initiale Admin wird einmalig im Supabase Dashboard erzeugt und per SQL mit der Schulrolle verknüpft. Weitere Benutzer werden über die Supabase Edge Function `create-user` angelegt. Die Funktion prüft den aufrufenden Admin und verwendet einen serverseitigen Supabase Secret Key.

Die Funktion kann mit der Supabase CLI bereitgestellt werden:

```sh
npx supabase login
npx supabase link --project-ref bqoxpwerrrsrfdvpelnh
npx supabase secrets set SUPABASE_SECRET_KEY=<NEUER_ROTIERTER_SECRET_KEY>
npx supabase functions deploy create-user
```

Ein Secret Key muss dabei ausschließlich als Edge-Function-Secret gesetzt werden; nie in GitHub Pages oder `.env` für den Browser.

## Funktionen und Grenzen

Enthalten: Supabase-Anmeldung, rollen- und schulbezogene RLS-Regeln, Klassen- und Schülerübersicht und -anlage, Anwesenheitssitzungen und Status, atomare Speicherung/Abschluss per PostgreSQL-Funktion, Änderungs-Audit für Anwesenheit, CSV-Berichte, Auswertungen, Schulprofil, Admin-Kontenanlage und GitHub-Pages-Workflow.

Noch offen: historische Klassenmitgliedschaften/Schuljahreswechsel, Schüler-Selbstzugang mit eigener Profilbeschränkung, Änderungsdialog für Klassen/Schüler, Lehrkraftzuordnung in der Oberfläche, Entschuldigungsbearbeitung, Stundenplan-/Konfliktverwaltung, Vertretungen, persistente interne Benachrichtigungen und automatisierte Unit-/Integrations-/E2E-Tests. Die Menüs hierfür sind teilweise nur Gerüste. Nicht für echte Schülerdaten oder produktiven Schuleinsatz freigegeben.

Anwesenheitsquote: (anwesend + verspätet) geteilt durch alle kontrollierten Einträge; nicht kontrollierte Einträge werden ausgeschlossen. Die DB-Funktion verhindert den Abschluss, wenn Einträge fehlen oder offen sind. Session-Tokens bleiben in `sessionStorage` und werden beim Schließen des Browser-Tabs entfernt.

Vor echtem Schulbetrieb müssen Datenschutzverantwortliche Hosting, Rechtsgrundlage, Auftragsverarbeitung, Berechtigungen, Aufbewahrung und Löschkonzept freigeben. Einrichten und testen: Backups, Wiederherstellung, Rate Limits und Auth-Mail-/Passwortabläufe.
