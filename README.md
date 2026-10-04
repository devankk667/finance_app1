# 💳 Nokai Finance

> A personal-finance ledger app — track income and expenses, set recurring entries, export to CSV, and get financial insights. **No bank linking. No money movement.**

[![Flutter](https://img.shields.io/badge/Flutter-3.29+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115+-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white)](https://python.org)

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
  - [1. Start the Backend](#1-start-the-backend)
  - [2. Start the Flutter App](#2-start-the-flutter-app)
- [Environment Variables](#environment-variables)
- [Production SMS (Twilio)](#production-sms-twilio)
- [Running Tests](#running-tests)
- [Known Limitations](#known-limitations)

---

## Overview

Nokai Finance is a full-stack personal-finance application. The **Flutter frontend** communicates with a **FastAPI backend** over a REST API protected by phone-based OTP authentication. All financial data is stored per-user; the backend enforces row-level access control so users can only read and modify their own transactions.

---

## Architecture

```
┌─────────────────────────────────┐        ┌──────────────────────────────────┐
│         Flutter Client          │        │          FastAPI Backend          │
│  (Web · Android · iOS · Desktop)│◄──────►│  /auth  /transactions  /summary  │
│                                 │  HTTP  │  /recurring  /export  /health    │
│  Provider state management      │  JWT   │                                  │
│  flutter_secure_storage tokens  │        │  SQLAlchemy ORM → SQLite (dev)   │
│  Offline read-only cache        │        │  PyJWT short-lived bearer tokens │
└─────────────────────────────────┘        │  Twilio Verify OTP (prod)        │
                                           └──────────────────────────────────┘
```

---

## Features

| Category | Details |
|---|---|
| 🔐 **Authentication** | Phone OTP login — mock (dev) or Twilio Verify (prod); short-lived JWT bearer tokens |
| 💸 **Transactions** | Create, edit, delete; search with filters by category, type, date range, and currency |
| 🔁 **Recurring Entries** | Daily, weekly, and monthly ledger templates |
| 📊 **Summaries** | Integer minor-unit amounts with per-currency totals; no FX conversion |
| 📤 **Export** | One-tap CSV export of your transaction history |
| 📱 **Offline Support** | Read-only cached data when the backend is unreachable |
| 💡 **Insights** | Built-in financial insights view |

---

## Project Structure

```
Finance_app/
├── backend/                  # FastAPI service
│   ├── app/
│   │   ├── main.py           # All route handlers
│   │   ├── models.py         # SQLAlchemy ORM models
│   │   ├── schemas.py        # Pydantic request/response schemas
│   │   ├── security.py       # JWT creation and verification
│   │   ├── otp.py            # OTP providers (mock + Twilio)
│   │   ├── config.py         # Settings via pydantic-settings
│   │   └── database.py       # DB engine and session factory
│   ├── tests/                # Pytest test suite
│   ├── requirements.txt
│   └── .env.example          # Template for environment variables
│
├── frontend/                 # Flutter application (primary)
│   ├── lib/
│   │   ├── core/             # App-wide config and constants
│   │   ├── data/             # API client and repository layer
│   │   ├── screens/          # Page-level UI
│   │   ├── widgets/          # Reusable UI components
│   │   ├── shared/           # Shared models and utilities
│   │   └── main.dart         # App entry point
│   └── pubspec.yaml
│
└── flutter_application_1/    # Starter scaffold (not the primary app)
```

---

## Prerequisites

| Requirement | Minimum version |
|---|---|
| [Flutter SDK](https://docs.flutter.dev/get-started/install) | 3.29 |
| [Python](https://www.python.org/downloads/) | 3.10 |
| [Git](https://git-scm.com/) | any recent |

> **Windows only:** Plugin builds may require **Developer Mode** to be enabled for symlink support. Enable it via *Settings → Privacy & Security → For Developers*.

---

## Quick Start

### 1. Start the Backend

Open a terminal at the repository root and set up a Python virtual environment:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Set the required environment variables and start the server **in the same session**:

```powershell
$env:APP_ENV        = "development"
$env:OTP_PROVIDER   = "mock"
$env:JWT_SECRET_KEY = "replace-with-a-random-secret-at-least-32-chars"

python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

> **Mock OTP:** In development mode the backend prints a 6-digit code to the console as `DEV OTP: 123456`. Codes expire after **5 minutes**, are **single-use**, and allow up to **5 attempts**. No SMS is ever sent. **Never enable mock OTP in production.**

Once running, verify the backend:

- Health check → <http://127.0.0.1:8000/health>
- Interactive API docs → <http://127.0.0.1:8000/docs>

---

### 2. Start the Flutter App

Open a **second terminal** at the repository root:

```powershell
cd frontend
flutter pub get
flutter run -d web-server --web-hostname localhost --web-port 3000 `
    --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Open <http://localhost:3000>, enter your phone number in **E.164 format** (e.g. `+919876543210`), then type the OTP that appeared in the backend console.

| Platform | `API_BASE_URL` |
|---|---|
| Web (localhost) | `http://127.0.0.1:8000` |
| Android Emulator | `http://10.0.2.2:8000` |
| Physical device | Your machine's local IP, e.g. `http://192.168.1.x:8000` |

---

## Environment Variables

Copy `backend/.env.example` and set the values as process environment variables (the backend does **not** auto-load `.env` files).

| Variable | Required | Default | Description |
|---|---|---|---|
| `JWT_SECRET_KEY` | ✅ | — | Random secret ≥ 32 characters for signing JWTs |
| `JWT_ALGORITHM` | optional | `HS256` | JWT signing algorithm |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | optional | `30` | Token lifetime in minutes |
| `DATABASE_URL` | optional | `sqlite:///./finance.db` | SQLAlchemy database URL |
| `CORS_ORIGINS` | optional | localhost ports | Comma-separated allowed origins |
| `APP_ENV` | ✅ | — | `development` or `production` |
| `OTP_PROVIDER` | ✅ | — | `mock` (dev) or `twilio` (prod) |
| `TWILIO_ACCOUNT_SID` | prod only | — | Twilio Account SID (`AC…`) |
| `TWILIO_AUTH_TOKEN` | prod only | — | Twilio Auth Token (or use API key + secret pair) |
| `TWILIO_VERIFY_SERVICE_SID` | prod only | — | Twilio Verify Service SID (`VA…`) |

---

## Production SMS (Twilio)

To send real OTPs, switch to the `twilio` provider by setting these variables before starting the backend:

```powershell
$env:APP_ENV                    = "production"
$env:OTP_PROVIDER               = "twilio"
$env:JWT_SECRET_KEY             = "<unique random secret ≥ 32 chars>"
$env:TWILIO_ACCOUNT_SID         = "AC..."
$env:TWILIO_AUTH_TOKEN          = "<auth token>"
$env:TWILIO_VERIFY_SERVICE_SID  = "VA..."
$env:CORS_ORIGINS               = "https://your-frontend.example"
```

You can use `TWILIO_API_KEY` + `TWILIO_API_SECRET` instead of `TWILIO_AUTH_TOKEN`.

> ⚠️ **Never commit credentials to source control.** Set `CORS_ORIGINS` to your exact deployed frontend origin in production.

---

## Running Tests

**Backend** (from `backend/`):

```powershell
cd backend
python -m pytest
```

**Flutter** (from `frontend/`):

```powershell
cd frontend
flutter analyze
flutter test
```

---

## Known Limitations

This is a **development foundation**, not a production financial service. Before going to production:

- [ ] Replace SQLite with a production database (PostgreSQL recommended) with migrations and backups.
- [ ] Add rate limiting, request validation hardening, and a security audit.
- [ ] Set up monitoring, structured logging, and alerting.
- [ ] Ensure `OTP_PROVIDER=mock` is **never** enabled in production.
- [ ] No bank account linking, payment processor, or money movement is implemented.

