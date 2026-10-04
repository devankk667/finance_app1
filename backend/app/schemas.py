import re
from datetime import date, datetime, timezone
from typing import Literal

from pydantic import (BaseModel, ConfigDict, Field, field_validator,
                      model_validator)


MAX_SAFE_MINOR_UNITS = 9_007_199_254_740_991


class PhoneRequest(BaseModel):
    phone_number: str = Field(pattern=r"^\+[1-9]\d{7,14}$")


class OTPVerifyRequest(PhoneRequest):
    code: str = Field(pattern=r"^\d{4,10}$")


class TokenResponse(BaseModel):
    access_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int


class TransactionCreate(BaseModel):
    amount_minor: int = Field(strict=True, gt=0, le=MAX_SAFE_MINOR_UNITS)
    currency: str = Field(pattern=r"^[A-Z]{3}$")
    transaction_type: Literal["income", "expense"]
    description: str = Field(min_length=1, max_length=200)
    category: str | None = Field(default=None, max_length=80)
    occurred_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    @field_validator("description", "category")
    @classmethod
    def strip_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        if not value:
            raise ValueError("Must contain non-whitespace characters")
        return value

    @field_validator("occurred_at")
    @classmethod
    def normalize_occurred_at(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)


class TransactionUpdate(BaseModel):
    amount_minor: int | None = Field(default=None, strict=True, gt=0, le=MAX_SAFE_MINOR_UNITS)
    currency: str | None = Field(default=None, pattern=r"^[A-Z]{3}$")
    transaction_type: Literal["income", "expense"] | None = None
    description: str | None = Field(default=None, min_length=1, max_length=200)
    category: str | None = Field(default=None, max_length=80)
    occurred_at: datetime | None = None

    @field_validator("description", "category")
    @classmethod
    def strip_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        if not value:
            raise ValueError("Must contain non-whitespace characters")
        return value

    @field_validator("currency")
    @classmethod
    def validate_currency(cls, value: str | None) -> str | None:
        if value is not None and not re.fullmatch(r"[A-Z]{3}", value):
            raise ValueError("Currency must be a three-letter uppercase ISO code")
        return value

    @field_validator("occurred_at")
    @classmethod
    def normalize_occurred_at(cls, value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)

    @model_validator(mode="after")
    def reject_null_required_fields(self) -> "TransactionUpdate":
        for field in ("amount_minor", "currency", "transaction_type", "description", "occurred_at"):
            if field in self.model_fields_set and getattr(self, field) is None:
                raise ValueError(f"{field} cannot be null")
        return self


class RecurringTemplateCreate(BaseModel):
    amount_minor: int = Field(strict=True, gt=0, le=MAX_SAFE_MINOR_UNITS)
    currency: str = Field(pattern=r"^[A-Z]{3}$")
    transaction_type: Literal["income", "expense"]
    description: str = Field(min_length=1, max_length=200)
    category: str | None = Field(default=None, max_length=80)
    frequency: Literal["daily", "weekly", "monthly"]
    start_date: date
    end_date: date | None = None

    @field_validator("description", "category")
    @classmethod
    def strip_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        if not value:
            raise ValueError("Must contain non-whitespace characters")
        return value

    @model_validator(mode="after")
    def end_not_before_start(self) -> "RecurringTemplateCreate":
        if self.end_date is not None and self.end_date < self.start_date:
            raise ValueError("end_date must be on or after start_date")
        return self


class RecurringTemplateResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    amount_minor: int
    currency: str
    transaction_type: Literal["income", "expense"]
    description: str
    category: str | None
    frequency: Literal["daily", "weekly", "monthly"]
    start_date: date
    end_date: date | None
    next_occurrence: date
    created_at: datetime


class TransactionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    amount_minor: int
    currency: str
    transaction_type: Literal["income", "expense"]
    description: str
    category: str | None
    occurred_at: datetime
    created_at: datetime


class MaterializedOccurrence(BaseModel):
    template_id: int
    occurrence_date: date
    transaction: TransactionResponse


class MaterializationResponse(BaseModel):
    as_of: date
    created_count: int
    occurrences: list[MaterializedOccurrence]


class TransactionSummaryResponse(BaseModel):
    balance_minor: int
    income_minor: int
    expense_minor: int
    currency: str = Field(pattern=r"^[A-Z]{3}$")
