# GoldBrain Frontend

Flutter application with the original animated screens, themes and language
selection. Authenticated sessions, live market quotes, verified history and
server forecasts use `lib/core/backend_api_client.dart`; provider and AI
credentials stay in the FastAPI backend.

Run the Windows client with a running backend:

```powershell
flutter pub get
$env:GOLDBRAIN_API_BASE_URL = 'http://127.0.0.1:8000'
flutter run -d windows
```

The base URL may be changed to an HTTPS deployment through the process
environment. Do not put provider credentials or the private backend key in
Flutter build arguments. Guest mode keeps the original local-only analysis
path; signing in enables the GoldBrain server market and forecast path.

Verify changes with:

```powershell
flutter analyze
flutter test
flutter build windows --release
```

See `README_LEGACY.md` for the original provider/audio setup notes from the prototype.
