# SchoolPresence

Responsive digitale Schul- und Anwesenheitsverwaltung. Das Frontend wird als statische Vite-App ausgeliefert; Supabase stellt PostgreSQL, Auth und abgesicherte Datenzugriffe bereit.

## Supabase-Projekt einrichten

1. Im SQL Editor der Reihe nach `supabase/migrations/202611110001_schoolpresence.sql` und `supabase/migrations/202611120002_extended_school_management.sql` vollständig ausführen. Zusammen erstellen sie Tabellen, Indizes, Funktionen, RLS-Regeln und ausschließlich fiktive Klassen-/Schülerdaten.
2. In **Authentication → Users** einen ersten Auth-Benutzer anlegen.
3. Im SQL Editor `supabase/bootstrap-admin.sql` ausführen. Die Datei verknüpft die mitgeteilte Auth-User-ID mit der Schule und Rolle `admin`.
4. In **Settings → API Keys** den **Publishable Key** ablesen. Nur dieser öffentliche Schlüssel kommt in die Browser-App. Einen `sb_secret_…`-Key niemals veröffentlichen oder in Browser-Konfiguration bzw. GitHub-Quellcode eintragen.
5. Für lokale Nutzung `.env.example` nach `.env` kopieren und die Projekt-URL sowie den Publishable Key eintragen.
6. In **Authentication → URL Configuration** die GitHub-Pages-Adresse `https://tayron0905.github.io/SchoolPresence/` als Site URL bzw. erlaubte Redirect URL hinterlegen, damit Passwort-Reset-Links zurück zur App führen.

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

## Demo- und Testdaten

Neue Installationen enthalten keine Beispielklassen oder Beispielschüler. Bereits eingerichtete Projekte können die ursprünglich erzeugten Demo-Einträge einmalig mit `supabase/cleanup-demo-data.sql` entfernen. Der Cleanup löscht Kennungen mit `DEMO-` und entfernt Beispielklassen samt Test-Unterrichtsdaten nur, wenn ihnen keine echten Schüler zugeordnet sind.

## GitHub Pages

Das Repository enthält einen Actions-Workflow unter `.github/workflows/deploy-pages.yml`. In den GitHub-Repository-Einstellungen unter **Secrets and variables → Actions** müssen diese Repository-Secrets gesetzt sein:

- `VITE_SUPABASE_URL` = `https://bqoxpwerrrsrfdvpelnh.supabase.co`
- `VITE_SUPABASE_PUBLISHABLE_KEY` = Publishable Key aus Supabase

Danach bei **Settings → Pages** die Bereitstellung über **GitHub Actions** aktivieren. Jeder Push auf `main` baut und veröffentlicht das Frontend. Der Publishable Key ist dafür vorgesehen, im Browser aufzutauchen; Row Level Security schützt die Daten. Der Secret Key darf nicht als Vite-Variable oder GitHub-Pages-Secret in den Frontend-Build gelangen.

## Benutzerverwaltung

Öffentliche Registrierung ist deaktiviert. Der initiale Admin wird einmalig im Supabase Dashboard erzeugt und per SQL mit der Schulrolle verknüpft. Weitere Benutzer werden über die Supabase Edge Function `create-user` angelegt. Die Funktion prüft den aufrufenden Admin und verwendet einen serverseitigen Supabase Secret Key.

Die Edge Functions für Anlage und Änderung von Benutzern müssen mit der Supabase CLI bereitgestellt werden. Sie lesen den projektseitig injizierten Supabase Secret Key; lege dafür keinen zusätzlichen Schlüssel in GitHub oder im Frontend ab:

```sh
npx supabase login
npx supabase link --project-ref bqoxpwerrrsrfdvpelnh
npx supabase functions deploy create-user
npx supabase functions deploy update-user
```

Der veröffentlichte Schlüssel, der im Frontend verwendet wird, ist ausschließlich der Publishable Key. Der Zugang zur App erfolgt mit persönlichen Supabase-Konten.

## Funktionen und Grenzen

Enthalten: Supabase-Anmeldung und Passwort-Reset/-Änderung, schulbezogene RLS, Klassen- und Schüleranlage/Bearbeitung/Archivierung, Klassenwechsel-Historie, Anwesenheitssitzungen mit atomarem Speichern und Abschließen, begründete Korrekturen, Fehlzeiten und geschützte interne Prüfanmerkungen, Schuljahre, Feiertage, Räume, Stundenplan mit Konfliktprüfung, Vertretungen mit Aufgabenbenachrichtigung, interne Benachrichtigungen, rollenbezogene CSV- und Druckberichte, Statistiken mit Zeitraumfiltern, Audit-Log und GitHub-Pages-Workflow.

Noch offen: Schüler-Selbstzugang, Schul-Logo/Unterrichtszeiten, Import, echte PDF-Erzeugung mit Kopf-/Fußzeile, Ferienkonflikte im Stundenplan GitHub Pages stellt das Frontend bereit; die beiden Edge Functions müssen noch mit der CLI deployed und beide SQL-Migrationen im Supabase-Projekt ausgeführt werden. Echte Daten erst nach Datenschutz- und Betriebsfreigabe verwenden.

Anwesenheitsquote: (anwesend + verspätet) geteilt durch alle kontrollierten Einträge; nicht kontrollierte Einträge werden ausgeschlossen. Die DB-Funktion verhindert den Abschluss, wenn Einträge fehlen oder offen sind. Session-Tokens bleiben in `sessionStorage` und werden beim Schließen des Browser-Tabs entfernt.

Vor echtem Schulbetrieb müssen Datenschutzverantwortliche Hosting, Rechtsgrundlage, Auftragsverarbeitung, Berechtigungen, Aufbewahrung und Löschkonzept freigeben. Backups, Wiederherstellung, Auth-Mail-/Passwortabläufe und die RLS-Regeln müssen vor Freigabe in der tatsächlichen Projektkonfiguration geprüft werden.
