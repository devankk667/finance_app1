# Nokai Finance

Flutter client for the Finance App API. It provides phone OTP sign-in, an authenticated personal ledger, transaction management, recurring ledger rules, insights, and CSV export. It does **not** link bank accounts or execute payments.

## Requirements

- Flutter 3.29 or later (validated with Flutter 3.47.6 / Dart 3.13.5)
- Python 3.10 or later for the API
- Twilio Verify credentials only if you want production SMS; local development can use the mock OTP provider

## Start the backend

From `backend/`, create a virtual environment and install dependencies as described in [`../backend/README.md`](../backend/README.md). For local development, set `OTP_PROVIDER=mock` and a random `JWT_SECRET_KEY` (at least 32 characters) in the server process. The generated OTP appears in the backend console as `DEV OTP: ...`; no SMS is sent. The backend does not load `.env` automatically.

For a local Flutter web session served at `http://localhost:3000`, set `CORS_ORIGINS=http://localhost:3000` and run:

```sh
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

## Run the Flutter client

From `frontend/`:

```sh
../flutter/bin/flutter pub get
../flutter/bin/flutter run -d web-server --web-hostname localhost --web-port 3000 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Open `http://localhost:3000` in a browser. For Android emulators, use `--dart-define=API_BASE_URL=http://10.0.2.2:8000`. Physical devices need the development machine's LAN address, a trusted network, and a matching `CORS_ORIGINS` entry for web.

The login screen uses E.164 phone numbers with either provider. In local mock mode, enter the OTP printed in the backend console; the code expires after five minutes and is single-use. For real SMS, set `OTP_PROVIDER=twilio` and configure a Verify service and credentials. Twilio delivery and charges depend on account configuration and destination country.

## Features

- OTP authentication through a selectable development mock or Twilio Verify provider, with short-lived bearer tokens.
- Per-user transaction create, edit, delete, search, category/type/date/currency filters, and CSV export copied to the clipboard.
- Recurring ledger templates for daily, weekly, or monthly entries. Due entries materialize when the app syncs; they are **not** bank payments.
- Currency-specific integer minor-unit totals. Supported display currencies are USD, EUR, GBP, INR, CAD, and AUD. Values are not converted between currencies.
- Offline read-only cache and session token stored with `flutter_secure_storage`; signing out clears the cached account data.
- Account summary, seven-day activity, category totals, and 28-day transaction activity.

## Validate

```sh
../flutter/bin/flutter analyze
../flutter/bin/flutter test
```

Backend tests:

```sh
cd ../backend
python -m pytest
```

## Important limitations

- No bank account provider is integrated. Plaid Sandbox is the proposed provider for read-only account linking and transaction import; credentials, account configuration, and the provider's Link UI are not present yet.
- No payment processor or money-movement flow is configured. Recurring rules only write ledger entries. Selecting a payment rail/provider requires defining supported countries, transaction direction, account onboarding, and compliance requirements.
- The mock OTP provider is development-only: codes are logged, kept in memory, and are not rate-limited. The backend also uses SQLite and short-lived JWTs without refresh/revocation; it is a development foundation, not production-ready.
- The client keeps its bearer token and up to 100 cached transactions in platform secure storage. The server database still needs a production database, managed encryption, backups, migrations, rate limiting, monitoring, and a privacy/security review.
- Offline mode is read-only; writes require a reachable API.
- Windows desktop builds using plugins require Windows Developer Mode/symlink support.
