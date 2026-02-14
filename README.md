# Vodafone Site Lookup (Offline)

This Flutter app searches **Site ID -> Latitude/Longitude** using an **offline SQLite DB** embedded in the app.

## Included DB
- assets/vodafone_sites.db
- Rows: 69622

## Run
1. Install Flutter (stable) and Android Studio.
2. In this folder:
   - `flutter pub get`
   - `flutter run`

## Build AAB for Google Play
- `flutter build appbundle`

## Replace / Update DB
Rebuild `assets/vodafone_sites.db` (table: `sites(site_id TEXT PRIMARY KEY, latitude REAL, longitude REAL)`) then rebuild the app.


## Added
- Splash screen + logo (assets/logo.png)
- Share on WhatsApp button + generic share sheet
