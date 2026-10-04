import hmac
import logging
import secrets
import time
from collections.abc import Callable

from fastapi import HTTPException

from app.config import Settings

logger = logging.getLogger(__name__)


class VerifyClient:
    def send_code(self, phone_number: str) -> str:
        raise NotImplementedError

    def check_code(self, phone_number: str, code: str) -> str:
        raise NotImplementedError


class MockVerifyClient(VerifyClient):
    """Development-only in-memory OTP provider that never sends SMS."""

    def __init__(self, *, ttl_seconds: int = 300, max_attempts: int = 5) -> None:
        self._ttl_seconds = ttl_seconds
        self._max_attempts = max_attempts
        self._codes: dict[str, tuple[str, float, int]] = {}

    def send_code(self, phone_number: str) -> str:
        code = f"{secrets.randbelow(1_000_000):06d}"
        self._codes[phone_number] = (code, time.monotonic() + self._ttl_seconds, 0)
        logger.warning("DEV OTP: %s", code)
        return "pending"

    def check_code(self, phone_number: str, code: str) -> str:
        issued = self._codes.get(phone_number)
        if issued is None:
            return "pending"

        expected, expires_at, attempts = issued
        if time.monotonic() >= expires_at:
            self._codes.pop(phone_number, None)
            return "pending"

        attempts += 1
        if hmac.compare_digest(expected, code):
            self._codes.pop(phone_number, None)
            return "approved"
        if attempts >= self._max_attempts:
            self._codes.pop(phone_number, None)
        else:
            self._codes[phone_number] = (expected, expires_at, attempts)
        return "pending"


class TwilioVerifyClient(VerifyClient):
    def __init__(
        self,
        settings: Settings,
        *,
        client_factory: Callable[..., object] | None = None,
    ) -> None:
        account_sid = settings.twilio_account_sid
        api_key = settings.twilio_api_key
        api_secret = settings.twilio_api_secret
        auth_token = settings.twilio_auth_token
        service_sid = settings.twilio_verify_service_sid
        if account_sid is None or service_sid is None:
            raise HTTPException(
                status_code=503,
                detail="Phone verification is not configured. Set the Twilio Verify environment variables.",
            )
        if client_factory is None:
            try:
                from twilio.rest import Client
            except ImportError as exc:
                raise HTTPException(
                    status_code=503,
                    detail="Twilio mode requires the backend dependencies. Install backend/requirements.txt.",
                ) from exc
            client_factory = Client
        if api_key is not None and api_secret is not None:
            self.client = client_factory(
                api_key,
                api_secret.get_secret_value(),
                account_sid=account_sid,
            )
        elif auth_token is not None:
            self.client = client_factory(account_sid, auth_token.get_secret_value())
        else:
            raise HTTPException(
                status_code=503,
                detail="Phone verification credentials are missing. Set Twilio API key credentials or an auth token.",
            )
        self.service_sid = service_sid

    def send_code(self, phone_number: str) -> str:
        try:
            result = self.client.verify.v2.services(self.service_sid).verifications.create(
                to=phone_number, channel="sms"
            )
        except Exception as exc:
            raise HTTPException(status_code=502, detail="Twilio could not start phone verification") from exc
        if result.status is None:
            raise HTTPException(status_code=502, detail="Twilio returned no verification status")
        return result.status

    def check_code(self, phone_number: str, code: str) -> str:
        try:
            result = self.client.verify.v2.services(self.service_sid).verification_checks.create(
                to=phone_number, code=code
            )
        except Exception as exc:
            raise HTTPException(status_code=502, detail="Twilio could not check phone verification") from exc
        if result.status is None:
            raise HTTPException(status_code=502, detail="Twilio returned no verification status")
        return result.status
