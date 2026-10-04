import builtins
import logging
import re

import pytest
from fastapi.testclient import TestClient
from pydantic import SecretStr

from app.config import Settings
from app.main import create_app, get_verify_client
from app.otp import MockVerifyClient, TwilioVerifyClient


class FakeVerifyClient:
    def __init__(self) -> None:
        self.sent_to: list[str] = []

    def send_code(self, phone_number: str) -> str:
        self.sent_to.append(phone_number)
        return "pending"

    def check_code(self, phone_number: str, code: str) -> str:
        return "approved" if code == "123456" else "pending"


@pytest.fixture
def client():
    settings = Settings(
        jwt_secret_key=SecretStr("test-signing-secret-that-is-at-least-32-chars"),
        database_url="sqlite://",
    )
    app = create_app(settings=settings, database_url="sqlite://")
    verify_client = FakeVerifyClient()
    app.dependency_overrides[get_verify_client] = lambda: verify_client
    with TestClient(app) as test_client:
        yield test_client


def test_cors_allows_dynamic_loopback_ports_only_in_development() -> None:
    origin = "http://localhost:53771"
    request_headers = {
        "Origin": origin,
        "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "content-type",
    }

    development_app = create_app(
        settings=Settings(
            jwt_secret_key=SecretStr("test-signing-secret-that-is-at-least-32-chars"),
            app_env="development",
        ),
        database_url="sqlite://",
    )
    with TestClient(development_app) as client:
        development_response = client.options("/auth/otp/start", headers=request_headers)
    assert development_response.status_code == 200
    assert development_response.headers["access-control-allow-origin"] == origin

    production_app = create_app(
        settings=Settings(
            jwt_secret_key=SecretStr("test-signing-secret-that-is-at-least-32-chars"),
            app_env="production",
        ),
        database_url="sqlite://",
    )
    with TestClient(production_app) as client:
        production_response = client.options("/auth/otp/start", headers=request_headers)
    assert production_response.status_code == 400


def sign_in(client: TestClient, phone_number: str) -> str:
    started = client.post("/auth/otp/start", json={"phone_number": phone_number})
    assert started.status_code == 202
    assert started.json()["status"] == "pending"
    response = client.post(
        "/auth/otp/verify",
        json={"phone_number": phone_number, "code": "123456"},
    )
    assert response.status_code == 200
    return response.json()["access_token"]


def test_phone_otp_and_per_user_transaction_crud(client: TestClient) -> None:
    first_token = sign_in(client, "+14155550101")
    second_token = sign_in(client, "+14155550102")
    first_headers = {"Authorization": f"Bearer {first_token}"}
    second_headers = {"Authorization": f"Bearer {second_token}"}

    create_response = client.post(
        "/transactions",
        headers=first_headers,
        json={
            "amount_minor": 1299,
            "currency": "USD",
            "transaction_type": "expense",
            "description": "Lunch",
            "category": "Food",
        },
    )
    assert create_response.status_code == 201
    transaction = create_response.json()
    transaction_id = transaction["id"]
    assert transaction["amount_minor"] == 1299
    assert transaction["currency"] == "USD"

    assert client.get("/transactions", headers=first_headers).json() == [transaction]
    assert client.get("/transactions", headers=second_headers).json() == []

    hidden = client.get(f"/transactions/{transaction_id}", headers=second_headers)
    assert hidden.status_code == 404
    hidden_update = client.patch(
        f"/transactions/{transaction_id}",
        headers=second_headers,
        json={"description": "Changed by another user"},
    )
    assert hidden_update.status_code == 404
    hidden_delete = client.delete(f"/transactions/{transaction_id}", headers=second_headers)
    assert hidden_delete.status_code == 404

    updated = client.patch(
        f"/transactions/{transaction_id}",
        headers=first_headers,
        json={"amount_minor": 2500, "description": "Updated lunch"},
    )
    assert updated.status_code == 200
    assert updated.json()["amount_minor"] == 2500
    assert updated.json()["description"] == "Updated lunch"

    deleted = client.delete(f"/transactions/{transaction_id}", headers=first_headers)
    assert deleted.status_code == 204
    assert client.get(f"/transactions/{transaction_id}", headers=first_headers).status_code == 404


def test_transaction_validation_and_authentication(client: TestClient) -> None:
    unauthenticated = client.get("/transactions")
    assert unauthenticated.status_code == 401

    token = sign_in(client, "+14155550103")
    headers = {"Authorization": f"Bearer {token}"}
    invalid_payloads = [
        {"amount_minor": -1, "currency": "USD", "transaction_type": "expense", "description": "x"},
        {"amount_minor": 100, "currency": "usd", "transaction_type": "expense", "description": "x"},
        {"amount_minor": 100.5, "currency": "USD", "transaction_type": "expense", "description": "x"},
        {"amount_minor": 9_007_199_254_740_992, "currency": "USD", "transaction_type": "expense", "description": "x"},
        {"amount_minor": 100, "currency": "USD", "transaction_type": "transfer", "description": "x"},
        {"amount_minor": 100, "currency": "USD", "transaction_type": "income", "description": "   "},
    ]
    for payload in invalid_payloads:
        response = client.post("/transactions", headers=headers, json=payload)
        assert response.status_code == 422

    created = client.post(
        "/transactions",
        headers=headers,
        json={
            "amount_minor": 100,
            "currency": "USD",
            "transaction_type": "income",
            "description": "Allowance",
        },
    )
    null_update = client.patch(
        f"/transactions/{created.json()['id']}", headers=headers, json={"amount_minor": None}
    )
    assert null_update.status_code == 422

    invalid_phone = client.post("/auth/otp/start", json={"phone_number": "555-0100"})
    assert invalid_phone.status_code == 422
    denied = client.post(
        "/auth/otp/verify",
        json={"phone_number": "+14155550103", "code": "000000"},
    )
    assert denied.status_code == 400


def test_transaction_filters_csv_export_and_tenant_scope(client: TestClient) -> None:
    token = sign_in(client, "+14155550105")
    headers = {"Authorization": f"Bearer {token}"}
    transactions = [
        {
            "amount_minor": 850,
            "currency": "USD",
            "transaction_type": "expense",
            "description": "Coffee and pastry",
            "category": "Food",
            "occurred_at": "2025-03-02T09:00:00-05:00",
        },
        {
            "amount_minor": 500000,
            "currency": "USD",
            "transaction_type": "income",
            "description": "Monthly salary",
            "category": "Income",
            "occurred_at": "2025-03-10T12:00:00Z",
        },
        {
            "amount_minor": 1200,
            "currency": "EUR",
            "transaction_type": "expense",
            "description": "Coffee shop",
            "category": "Food",
            "occurred_at": "2025-04-02T09:00:00Z",
        },
        {
            "amount_minor": 100,
            "currency": "USD",
            "transaction_type": "expense",
            "description": "=HYPERLINK(\"https://bad.invalid\")",
            "category": "Food",
            "occurred_at": "2025-03-15T09:00:00Z",
        },
    ]
    for transaction in transactions:
        assert client.post("/transactions", headers=headers, json=transaction).status_code == 201

    filtered = client.get(
        "/transactions",
        headers=headers,
        params={
            "search": "Coffee",
            "category": "food",
            "transaction_type": "expense",
            "date_from": "2025-03-01",
            "date_to": "2025-03-31",
            "currency": "USD",
        },
    )
    assert filtered.status_code == 200
    assert len(filtered.json()) == 1
    assert filtered.json()[0]["description"] == "Coffee and pastry"
    assert filtered.json()[0]["occurred_at"].startswith("2025-03-02T14:00:00")

    exported = client.get(
        "/transactions/export.csv",
        headers=headers,
        params={"search": "HYPERLINK", "currency": "USD"},
    )
    assert exported.status_code == 200
    assert exported.headers["content-type"].startswith("text/csv")
    assert "'=HYPERLINK" in exported.text
    assert "Monthly salary" not in exported.text

    assert client.get("/transactions/export.csv").status_code == 401
    invalid_range = client.get(
        "/transactions", headers=headers, params={"date_from": "2025-04-01", "date_to": "2025-03-01"}
    )
    assert invalid_range.status_code == 422

    other_headers = {"Authorization": f"Bearer {sign_in(client, '+14155550106')}"}
    other_user_export = client.get(
        "/transactions/export.csv", headers=other_headers, params={"search": "Coffee"}
    )
    assert other_user_export.status_code == 200
    assert "Coffee" not in other_user_export.text


def test_recurring_templates_are_scoped_and_due_materialization_is_idempotent(
    client: TestClient,
) -> None:
    owner_headers = {"Authorization": f"Bearer {sign_in(client, '+14155550107')}"}
    other_headers = {"Authorization": f"Bearer {sign_in(client, '+14155550108')}"}
    template_payload = {
        "amount_minor": 2599,
        "currency": "USD",
        "transaction_type": "expense",
        "description": "Monthly membership",
        "category": "Subscriptions",
        "frequency": "monthly",
        "start_date": "2025-01-30",
        "end_date": "2025-04-30",
    }

    created = client.post("/recurring-templates", headers=owner_headers, json=template_payload)
    assert created.status_code == 201
    template_id = created.json()["id"]
    assert created.json()["next_occurrence"] == "2025-01-30"
    assert client.post("/recurring-templates", json=template_payload).status_code == 401
    assert client.get("/recurring-templates", headers=other_headers).json() == []

    invalid_template = {**template_payload, "end_date": "2024-12-31"}
    assert client.post(
        "/recurring-templates", headers=owner_headers, json=invalid_template
    ).status_code == 422

    endpoint = "/recurring-templates/materialize-due"
    assert client.post(endpoint, params={"as_of": "2025-04-30"}).status_code == 401
    non_owner_run = client.post(endpoint, headers=other_headers, params={"as_of": "2025-04-30"})
    assert non_owner_run.status_code == 200
    assert non_owner_run.json()["created_count"] == 0

    first_batch = client.post(
        endpoint,
        headers=owner_headers,
        params={"as_of": "2025-04-30", "max_occurrences": 2},
    )
    assert first_batch.status_code == 200
    assert [item["occurrence_date"] for item in first_batch.json()["occurrences"]] == [
        "2025-01-30",
        "2025-02-28",
    ]
    second_batch = client.post(
        endpoint,
        headers=owner_headers,
        params={"as_of": "2025-04-30", "max_occurrences": 2},
    )
    assert [item["occurrence_date"] for item in second_batch.json()["occurrences"]] == [
        "2025-03-30",
        "2025-04-30",
    ]
    assert all(item["transaction"]["amount_minor"] == 2599 for item in second_batch.json()["occurrences"])
    retry = client.post(endpoint, headers=owner_headers, params={"as_of": "2025-04-30"})
    assert retry.status_code == 200
    assert retry.json()["created_count"] == 0
    assert len(client.get("/transactions", headers=owner_headers).json()) == 4
    assert client.get("/recurring-templates", headers=owner_headers).json()[0]["next_occurrence"] == "2025-05-30"

    assert client.delete(
        f"/recurring-templates/{template_id}", headers=other_headers
    ).status_code == 404
    assert client.delete(f"/recurring-templates/{template_id}", headers=owner_headers).status_code == 204
    assert client.get("/recurring-templates", headers=owner_headers).json() == []
    assert len(client.get("/transactions", headers=owner_headers).json()) == 4


def test_transaction_summary_uses_signed_type_totals_and_tenant_currency_scope(
    client: TestClient,
) -> None:
    owner_headers = {"Authorization": f"Bearer {sign_in(client, '+14155550109')}"}
    other_headers = {"Authorization": f"Bearer {sign_in(client, '+14155550110')}"}

    ledger_entries = [
        ("income", 10000, "USD"),
        ("expense", 4000, "USD"),
        ("expense", 8000, "USD"),
        ("income", 777, "EUR"),
    ]
    for transaction_type, amount_minor, currency in ledger_entries:
        response = client.post(
            "/transactions",
            headers=owner_headers,
            json={
                "amount_minor": amount_minor,
                "currency": currency,
                "transaction_type": transaction_type,
                "description": "Summary test entry",
            },
        )
        assert response.status_code == 201

    other_user_entry = client.post(
        "/transactions",
        headers=other_headers,
        json={
            "amount_minor": 500000,
            "currency": "USD",
            "transaction_type": "income",
            "description": "Other user's income",
        },
    )
    assert other_user_entry.status_code == 201

    usd_summary = client.get("/transactions/summary", headers=owner_headers, params={"currency": "USD"})
    assert usd_summary.status_code == 200
    assert usd_summary.json() == {
        "balance_minor": -2000,
        "income_minor": 10000,
        "expense_minor": 12000,
        "currency": "USD",
    }

    eur_summary = client.get("/transactions/summary", headers=owner_headers, params={"currency": "EUR"})
    assert eur_summary.json() == {
        "balance_minor": 777,
        "income_minor": 777,
        "expense_minor": 0,
        "currency": "EUR",
    }
    empty_summary = client.get(
        "/transactions/summary", headers=owner_headers, params={"currency": "GBP"}
    )
    assert empty_summary.json() == {
        "balance_minor": 0,
        "income_minor": 0,
        "expense_minor": 0,
        "currency": "GBP",
    }

    assert client.get("/transactions/summary", params={"currency": "USD"}).status_code == 401
    assert client.get("/transactions/summary", headers=owner_headers).status_code == 422
    assert client.get(
        "/transactions/summary", headers=owner_headers, params={"currency": "usd"}
    ).status_code == 422
    assert client.get(
        "/transactions/summary", headers=owner_headers, params={"currency": "US"}
    ).status_code == 422


def test_mock_otp_logs_code_and_authenticates_without_sms(
    caplog: pytest.LogCaptureFixture,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("OTP_PROVIDER", "mock")
    import_with_twilio_available = builtins.__import__

    def import_without_twilio(name: str, *args: object, **kwargs: object) -> object:
        if name == "twilio" or name.startswith("twilio."):
            raise ModuleNotFoundError("Twilio SDK intentionally unavailable in this test")
        return import_with_twilio_available(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", import_without_twilio)
    settings = Settings(
        jwt_secret_key=SecretStr("test-signing-secret-that-is-at-least-32-chars"),
        database_url="sqlite://",
    )
    app = create_app(settings=settings, database_url="sqlite://")
    phone_number = "+14155550106"

    with caplog.at_level(logging.WARNING, logger="app.otp"):
        with TestClient(app) as test_client:
            started = test_client.post("/auth/otp/start", json={"phone_number": phone_number})
            assert started.status_code == 202
            assert started.json()["status"] == "pending"
            assert "DEV OTP" not in started.text

            match = re.search(r"DEV OTP: (\d{6})", caplog.text)
            assert match is not None
            code = match.group(1)

            verified = test_client.post(
                "/auth/otp/verify",
                json={"phone_number": phone_number, "code": code},
            )
            assert verified.status_code == 200
            assert verified.json()["access_token"]

            replayed = test_client.post(
                "/auth/otp/verify",
                json={"phone_number": phone_number, "code": code},
            )
            assert replayed.status_code == 400


def test_mock_otp_limits_failed_attempts(caplog: pytest.LogCaptureFixture) -> None:
    provider = MockVerifyClient(max_attempts=2)
    with caplog.at_level(logging.WARNING, logger="app.otp"):
        provider.send_code("+14155550107")
    match = re.search(r"DEV OTP: (\d{6})", caplog.text)
    assert match is not None

    wrong_code = "000000" if match.group(1) != "000000" else "000001"
    assert provider.check_code("+14155550107", wrong_code) == "pending"
    assert provider.check_code("+14155550107", wrong_code) == "pending"
    assert provider.check_code("+14155550107", match.group(1)) == "pending"


def test_twilio_api_key_credentials_configure_client() -> None:
    calls: list[tuple[tuple[object, ...], dict[str, object]]] = []

    def fake_client(*args: object, **kwargs: object) -> object:
        calls.append((args, kwargs))
        return object()

    settings = Settings(
        jwt_secret_key=SecretStr("test-signing-secret-that-is-at-least-32-chars"),
        twilio_account_sid="ACtest",
        twilio_api_key="SKtest",
        twilio_api_secret=SecretStr("api-secret"),
        twilio_verify_service_sid="VAtest",
    )

    client = TwilioVerifyClient(settings, client_factory=fake_client)

    assert client.service_sid == "VAtest"
    assert calls == [(("SKtest", "api-secret"), {"account_sid": "ACtest"})]


def test_twilio_configuration_is_required_for_real_otp() -> None:
    settings = Settings(
        jwt_secret_key=SecretStr("test-signing-secret-that-is-at-least-32-chars"),
        database_url="sqlite://",
    )
    app = create_app(settings=settings, database_url="sqlite://")
    with TestClient(app) as client:
        response = client.post("/auth/otp/start", json={"phone_number": "+14155550104"})
    assert response.status_code == 503
    assert "not configured" in response.json()["detail"]
