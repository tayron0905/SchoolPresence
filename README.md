# SchoolPresence

Responsive digitale Schul- und Anwesenheitsverwaltung. Das Frontend wird als statische Vite-App ausgeliefert; Supabase stellt PostgreSQL, Auth und abgesicherte Datenzugriffe bereit.

## Supabase-Projekt einrichten

1. Im SQL Editor der Reihe nach `supabase/migrations/202611110001_schoolpresence.sql`, `supabase/migrations/202611120002_extended_school_management.sql` und `supabase/migrations/202611130003_user_deletion.sql` vollständig ausführen. Zusammen erstellen sie Tabellen, Indizes, Funktionen und RLS-Regeln. Neue Installationen erhalten keine Beispielklassen oder Beispieldatensätze.
2. In **Authentication → Users** einen ersten Auth-Benutzer anlegen.
3. Im SQL Editor `supabase/bootstrap-admin.sql` ausführen. Die Datei verknüpft die mitgeteilte Auth-User-ID mit der Schule und Rolle `admin`.
4. In **Settings → API Keys** den **Publishable Key** ablesen. Nur dieser öffentliche Schlüssel kommt in die Browser-App. Einen `sb_secret_…`-Key niemals veröffentlichen oder in Browser-Konfiguration bzw. GitHub-Quellcode eintragen.
5. Für lokale Nutzung `.env.example` nach `.env` kopieren und die Projekt-URL sowie den Publishable Key eintragen.
6. In **Authentication → URL Configuration** die GitHub-Pages-Adresse `https://tayron0905.github.io/SchoolPresence/` als Site URL bzw. erlaubte Redirect URL hinterlegen, damit Passwort-Reset-Links zurück zur App führen.

Die Supabase-URL des verknüpften Projekts lautet `https://bqoxpwerrrsrfdvpelnh.supabase.co`.

## Lokal starten

Voraussetzung: Node.js 22 oder neuer.

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

## Mobile-Apps (Android und iPhone)

Die native App verwendet dieselbe Oberfläche und dasselbe Supabase-Projekt wie die Website, ohne deren Quellcode oder veröffentlichte Oberfläche zu ändern. `vite.mobile.config.mjs` erzeugt relative Asset-Pfade in `dist-mobile`; Capacitor kopiert diese in die Android- und iOS-Projekte. Die App-ID lautet `de.tayron0905.schoolpresence`.

```sh
npm ci
npm run mobile:sync
```

Lokal kannst du ein Android-Debug-APK mit `npm run android:debug` bauen, wenn Android Studio und das Android SDK installiert sind. Der Workflow **Build mobile apps** erstellt außerdem ein Android-Debug-APK und einen iOS-Simulator-Build. Die Artefakte stehen nach einem erfolgreichen Lauf unter GitHub → **Actions** bereit. Das Android-Debug-APK lässt sich zum Testen auf Android installieren; für eine Play-Store-Veröffentlichung braucht es später ein Release-Keystore und Google-Play-Einrichtung.

### Apple-Signierung ohne Mac

CachyOS kann für die Apple-Webportale und die CSR-Erstellung verwendet werden. Xcode selbst läuft auf dem macOS-Runner in GitHub Actions. Für einen signierten IPA-Build brauchst du eine Apple-Developer-Program-Mitgliedschaft, eine App-ID `de.tayron0905.schoolpresence`, ein Apple-Distribution-Zertifikat und ein App-Store-Connect-Provisioning-Profil. Für automatischen TestFlight-Upload brauchst du zusätzlich einen App-Store-Connect-API-Schlüssel und einen angelegten App-Store-Connect-App-Eintrag.

1. Registriere dich im Browser beim [Apple Developer Program](https://developer.apple.com/programs/enroll/).
2. Der CSR wurde bereits auf diesem CachyOS-PC erzeugt: `~/SchoolPresence-Apple-Signing/apple-distribution.csr`. Falls du ein neues Zertifikatsschlüsselpaar brauchst, kannst du im Repository `bash mobile/apple-signing/generate-csr.sh` ausführen. Der private `.key`-Schlüssel bleibt im Home-Ordner und darf nicht geteilt werden.
3. Im Apple Developer Account unter **Certificates, Identifiers & Profiles** die Bundle-ID `de.tayron0905.schoolpresence` registrieren, mit der CSR ein **Apple Distribution**-Zertifikat erstellen und ein App-Store-Connect-Profil für diese App-ID erzeugen.
4. Das heruntergeladene Zertifikat und Profil auf CachyOS in ein P12 und Base64-Dateien umwandeln:

   ```sh
   cd ~/SchoolPresence-Apple-Signing
   openssl x509 -inform DER -in distribution.cer -out distribution.pem
   openssl pkcs12 -export -inkey apple-distribution.key -in distribution.pem -out apple-distribution.p12
   base64 -w0 apple-distribution.p12 > apple-distribution.p12.base64
   base64 -w0 SchoolPresence.mobileprovision > SchoolPresence.mobileprovision.base64
   ```

   Bei `openssl pkcs12` ein starkes Export-Passwort setzen. Die `.p12` enthält den privaten Signierschlüssel und muss vertraulich bleiben.
5. In GitHub unter **Settings → Secrets and variables → Actions** diese Repository-Secrets anlegen: `APPLE_CERTIFICATE_BASE64` (Inhalt der `.p12.base64`-Datei), `APPLE_CERTIFICATE_PASSWORD`, `APPLE_PROVISIONING_PROFILE_BASE64` (Inhalt der `.mobileprovision.base64`-Datei), `APPLE_TEAM_ID`. Der Workflow liest den Profilnamen aus der heruntergeladenen Provisioning-Profile-Datei.
6. Unter **Actions → Sign iOS app → Run workflow** den signierten Build starten. Das signierte IPA erscheint als Workflow-Artefakt. Wähle `upload_to_testflight` erst, wenn zusätzlich `APPSTORE_API_KEY_ID`, `APPSTORE_ISSUER_ID` und `APPSTORE_API_PRIVATE_KEY` als Secrets eingerichtet sind und der App-Eintrag in App Store Connect existiert.

Weder Apple-Passwort noch Zertifikat, private Schlüssel, Profil oder API-Key hier im Chat posten. Diese Werte gehören nur in Apple-Portale, auf deinen Rechner und in GitHub Actions Secrets.

## Funktionen und Grenzen

Enthalten: Supabase-Anmeldung und Passwort-Reset/-Änderung, schulbezogene RLS, Klassen- und Schüleranlage/Bearbeitung/Archivierung, Klassenwechsel-Historie, Anwesenheitssitzungen mit atomarem Speichern und Abschließen, begründete Korrekturen, Fehlzeiten und geschützte interne Prüfanmerkungen, Schuljahre, Feiertage, Räume, Stundenplan mit Konfliktprüfung, Vertretungen mit Aufgabenbenachrichtigung, interne Benachrichtigungen, rollenbezogene CSV- und Druckberichte, Statistiken mit Zeitraumfiltern, Audit-Log und GitHub-Pages-Workflow.

Noch offen: Schüler-Selbstzugang, Schul-Logo/Unterrichtszeiten, Import, echte PDF-Erzeugung mit Kopf-/Fußzeile und Ferienkonflikte im Stundenplan. GitHub Pages stellt das Frontend bereit. Die Edge Functions und die drei SQL-Migrationen müssen in neuen Supabase-Projekten bereitgestellt werden. Echte Daten erst nach Datenschutz- und Betriebsfreigabe verwenden.

Anwesenheitsquote: (anwesend + verspätet) geteilt durch alle kontrollierten Einträge; nicht kontrollierte Einträge werden ausgeschlossen. Die DB-Funktion verhindert den Abschluss, wenn Einträge fehlen oder offen sind. Session-Tokens bleiben in `sessionStorage` und werden beim Schließen des Browser-Tabs entfernt.

Vor echtem Schulbetrieb müssen Datenschutzverantwortliche Hosting, Rechtsgrundlage, Auftragsverarbeitung, Berechtigungen, Aufbewahrung und Löschkonzept freigeben. Backups, Wiederherstellung, Auth-Mail-/Passwortabläufe und die RLS-Regeln müssen vor Freigabe in der tatsächlichen Projektkonfiguration geprüft werden.
