# Finance App API

A development backend built with FastAPI, SQLAlchemy, and SQLite. It provides
Twilio Verify phone OTP authentication and per-user transaction CRUD. It does
not connect to banks, initiate payments, or process financial transactions.

## Requirements and setup

- Python 3.10 or newer
- A Twilio account with a configured Verify service to send real SMS codes
- Twilio Account SID, Auth Token, and Verify Service SID (keep these private)

From this directory, create and activate a virtual environment, then install
dependencies:

```sh
python -m venv .venv
# macOS/Linux
. .venv/bin/activate
# Windows PowerShell: .venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

Copy `.env.example` as a reference for the required variable names, then set
the values in your shell, IDE launch configuration, or deployment environment.
The application intentionally reads **process environment variables only**;
it does not load `.env`. Do not replace an existing local `.env` file. Generate
a unique random `JWT_SECRET_KEY` with at least 32 characters and configure:

- `JWT_SECRET_KEY` — required; used to sign short-lived HS256 access tokens.
- `JWT_ALGORITHM` — optional; defaults to `HS256`.
- `ACCESS_TOKEN_EXPIRE_MINUTES` — optional; defaults to 30.
- `DATABASE_URL` — optional; defaults to `sqlite:///./finance.db` in the
  current working directory.
- `APP_ENV` — `development` (default) allows loopback browser origins on any
  port for local Flutter development. Set to `production` to disable that
  development-only localhost rule.
- `CORS_ORIGINS` — comma-separated exact browser origins; defaults to localhost
  ports 3000, 5173, and 8000. In production, set this to the exact deployed
  frontend origins.
- `OTP_PROVIDER` — `twilio` (default, fail-closed) or `mock` for local
  development. Mock mode generates a six-digit code, logs it as `DEV OTP: ...`,
  expires it after five minutes, and never sends SMS. It is in-memory and must
  not be used in production.
- For `OTP_PROVIDER=twilio`, `TWILIO_ACCOUNT_SID` and
  `TWILIO_VERIFY_SERVICE_SID`, plus either `TWILIO_API_KEY` and
  `TWILIO_API_SECRET` or `TWILIO_AUTH_TOKEN`, are required. API keys are
  preferred over the account auth token.

Set variables in PowerShell, for example (replace the placeholders):

```powershell
$env:JWT_SECRET_KEY = "replace-with-your-own-random-secret-of-32-characters-or-more"
$env:APP_ENV = "development"
$env:OTP_PROVIDER = "mock" # local development; no SMS is sent
# Production: set APP_ENV to "production", OTP_PROVIDER to "twilio",
# and configure exact CORS_ORIGINS plus the Twilio values.
# $env:TWILIO_ACCOUNT_SID = "AC..."
# $env:TWILIO_API_KEY = "SK..."
# $env:TWILIO_API_SECRET = "..."
# $env:TWILIO_VERIFY_SERVICE_SID = "VA..."
```

Start the server from `backend/`:

```sh
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

Interactive API docs: <http://127.0.0.1:8000/docs>; health check:
<http://127.0.0.1:8000/health>.

### Development URLs and CORS

The API listens on `127.0.0.1:8000` by default. Flutter web/desktop can use
`http://127.0.0.1:8000`; Android emulators generally reach the host machine at
`http://10.0.2.2:8000`. For a physical device, bind with `--host 0.0.0.0` and
use the development machine's LAN IP, with both devices on a trusted network.
In development, any `localhost`, `127.0.0.1`, or `[::1]` browser origin is
accepted on any port. For production, set `APP_ENV=production` and configure
`CORS_ORIGINS` with the exact browser origins. CORS is a browser policy and does
not replace API authentication or network security. Do not expose the
development server to an untrusted network.

## API

- `POST /auth/otp/start` — `{ "phone_number": "+14155550123" }`
- `POST /auth/otp/verify` — phone number and numeric `code`; returns a bearer
  JWT only when Twilio Verify reports `approved`.
- `GET /transactions` — optional `search`, `category`, `transaction_type`,
  `date_from`, `date_to`, and `currency` filters, plus `limit`/`offset`.
  `search` matches description or category; category matching is
  case-insensitive exact matching. Date filters are inclusive ISO dates and are
  evaluated against UTC-normalized transaction timestamps.
- `GET /transactions/export.csv` — CSV download using the same filters.
  Formula-leading description/category cells are escaped for spreadsheet use.
- `GET /transactions/summary?currency=USD` — authenticated, full-ledger totals
  for one uppercase three-letter currency; returns `income_minor`,
  `expense_minor`, and `balance_minor` (`income - expense`) as integers.
  Currency totals are not converted or combined across currencies.
- `POST /transactions`
- `GET /transactions/{transaction_id}`
- `PATCH /transactions/{transaction_id}`
- `DELETE /transactions/{transaction_id}`
- `POST /recurring-templates` — create a user's recurring template.
- `GET /recurring-templates` — list the authenticated user's templates.
- `DELETE /recurring-templates/{template_id}` — delete a user's template;
  transactions already materialized from it are retained.
- `POST /recurring-templates/materialize-due?as_of=YYYY-MM-DD&max_occurrences=100`
  — materialize occurrences due through `as_of` (defaults to today UTC). The
  limit is 1–500 per request and future `as_of` dates are rejected. Repeat
  calls advance from each template's saved next date and do not duplicate
  previously committed occurrences; a database uniqueness constraint is a
  final duplicate guard. A concurrent conflicting request may return 409 and
  should be retried.

Transaction bodies use positive integer `amount_minor` (for example, 1299 for
USD 12.99), capped at JavaScript's exact-integer limit (9,007,199,254,740,991)
so web clients can preserve values exactly, and an uppercase three-letter currency code such as `USD`,
`transaction_type` (`income` or `expense`), a non-empty description, optional
category, and optional ISO-8601 `occurred_at`. Every transaction query/export is
scoped to the authenticated user; records belonging to another user return
404. Recurring template bodies use the same integer amount/currency/type/text
fields plus `frequency` (`daily`, `weekly`, or `monthly`), `start_date`, and
optional inclusive `end_date`. Occurrences are dated at midnight UTC. Monthly
schedules retain the start-date day where possible and clamp to the last day
of shorter months (for example, a day-30 schedule uses February 28/29 and
returns to day 30 the next month). Generated transactions remain ordinary
per-user transactions; materialization is explicit and no background scheduler
is started by this API.

## Tests

Tests use an injected fake Verify client and require no Twilio credentials:

```sh
python -m pytest
```

## Limitations before production

This is a development foundation, not a production-ready financial service.
Add per-phone/IP OTP and API rate limiting, abuse/fraud controls, monitoring,
and secure deployment secrets management. SQLite is intended for local
single-instance development; select and harden an appropriate production
database, backups, migrations, encryption, retention, and access controls.
The occurrence transaction uses a database uniqueness constraint and a single
commit with the generated transaction/template cursor update. Production
multi-worker deployments still need database-specific locking/retry policy and
load testing; SQLite's row locks are not equivalent to a server database. CSV
export currently buffers matching rows in memory, so add streaming/size limits
for large production datasets.
Review JWT key rotation/token revocation, HTTPS, privacy/compliance, and
operational recovery. Twilio SMS availability, delivery, and charges depend on
your Twilio configuration and destination country. No bank-data provider,
account-linking integration, or payment processor is configured or claimed.
