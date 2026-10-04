# Finance App workspace

The primary app is the Flutter client in [`frontend/`](frontend/), backed by the FastAPI service in [`backend/`](backend/README.md).

## Workspace folders

- `frontend/` — Nokai Finance Flutter app.
- `backend/` — development API with Twilio Verify OTP auth and per-user ledger endpoints.
- `flutter/` — Flutter SDK used by this workspace.
- `flutter_application_1/` — separate generated “Hello World” Flutter scaffold; it is not used by Nokai Finance.

See [`frontend/README.md`](frontend/README.md) for run instructions and known integration/security limits. Bank linking and real money movement are not active.
