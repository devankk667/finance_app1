# Nokai Finance

Nokai Finance is a Flutter personal-finance ledger backed by a FastAPI service. It supports manual income and expense tracking, recurring ledger entries, summaries, and CSV export. It does not link to bank accounts or move money.

## Project layout

- `frontend/` — Flutter application.
- `backend/` — FastAPI API, authentication, ledger, and backend tests.
- `flutter_application_1/` — separate starter Flutter scaffold; it is not the primary app.

## Requirements

- Flutter SDK 3.29 or newer.
- Python 3.10 or newer.

## Run locally

### 1. Start the backend

From the repository root, create a Python environment and install the backend dependencies:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

For local development, configure mock OTP authentication in the same PowerShell session. The backend reads process environment variables; it does not load `.env` files automatically.

```powershell
$env:APP_ENV = "development"
$env:OTP_PROVIDER = "mock"
$env:JWT_SECRET_KEY = "replace-with-a-random-secret-at-least-32-characters-long"
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

Mock mode logs a generated six-digit code as `DEV OTP: ...` in the backend console. Codes expire after five minutes, are single-use, and allow up to five attempts. No SMS is sent. **Mock OTP is for local development only.**

The API health endpoint is <http://127.0.0.1:8000/health>; interactive docs are at <http://127.0.0.1:8000/docs>.

### 2. Start the Flutter app

In a second terminal, from the repository root:

```powershell
cd frontend
flutter pub get
flutter run -d web-server --web-hostname localhost --web-port 3000 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Open <http://localhost:3000>, enter a phone number in E.164 format, then enter the OTP printed by the backend. In development, the API accepts loopback browser origins on any port. For Android emulators, set `API_BASE_URL` to `http://10.0.2.2:8000` instead.

On Windows, plugin builds may require Developer Mode to be enabled for symlink support.

## Production SMS configuration

Twilio Verify is optional for local mock development. To use real SMS, set these process environment variables and restart the backend:

```text
APP_ENV=production
OTP_PROVIDER=twilio
JWT_SECRET_KEY=<a unique random secret of at least 32 characters>
TWILIO_ACCOUNT_SID=AC...
TWILIO_API_KEY=SK...
TWILIO_API_SECRET=<secret>
TWILIO_VERIFY_SERVICE_SID=VA...
CORS_ORIGINS=https://your-frontend.example
```

The backend also supports `TWILIO_AUTH_TOKEN` in place of the API key and secret. Never commit credentials or put them in source control. Set `CORS_ORIGINS` to the exact deployed frontend origin(s) in production.

## Features

- Phone OTP authentication with development mock and Twilio Verify providers.
- Short-lived bearer sessions and per-user transaction access.
- Transaction create, edit, delete, search, and category/type/date/currency filters.
- Integer minor-unit amounts and currency-specific summaries; no foreign-exchange conversion.
- Daily, weekly, and monthly recurring ledger templates.
- CSV export, offline read-only cached data, and financial insights.

## Tests

Backend:

```powershell
cd backend
python -m pytest
```

Flutter, from `frontend/`:

```powershell
flutter analyze
flutter test
```

## Limitations and production work

This is a development foundation, not a production financial service. The backend currently uses SQLite and needs production database deployment, migrations, backups, rate limiting, monitoring, and security review. Mock OTP is insecure by design and must not be enabled in production. No bank-data provider, account linking, payment processor, or real money movement is configured.
