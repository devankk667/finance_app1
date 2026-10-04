import calendar
import csv
from contextlib import asynccontextmanager
from datetime import date, datetime, time, timedelta, timezone
from io import StringIO
from typing import Annotated, Literal

from fastapi import (Depends, FastAPI, HTTPException, Query, Request, Response,
                     status)
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import case, create_engine, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.config import Settings
from app.database import get_db
from app.models import (Base, RecurringOccurrence, RecurringTemplate,
                        Transaction, User)
from app.otp import MockVerifyClient, TwilioVerifyClient, VerifyClient
from app.schemas import (MaterializationResponse, MaterializedOccurrence,
                         OTPVerifyRequest, PhoneRequest,
                         RecurringTemplateCreate, RecurringTemplateResponse,
                         TokenResponse, TransactionCreate, TransactionResponse,
                         TransactionSummaryResponse, TransactionUpdate)
from app.security import authenticated_user, create_access_token


def get_verify_client(request: Request) -> VerifyClient:
    settings = request.app.state.settings
    if settings.otp_provider == "mock":
        return request.app.state.mock_verify_client
    return TwilioVerifyClient(settings)


CurrentUser = Annotated[User, Depends(authenticated_user)]
DatabaseSession = Annotated[Session, Depends(get_db)]
Verify = Annotated[VerifyClient, Depends(get_verify_client)]


def add_transaction_filters(
    statement,
    *,
    search: str | None = None,
    category: str | None = None,
    transaction_type: str | None = None,
    date_from: date | None = None,
    date_to: date | None = None,
    currency: str | None = None,
):
    if date_from is not None and date_to is not None and date_from > date_to:
        raise HTTPException(status_code=422, detail="date_from must be on or before date_to")
    if search is not None:
        search = search.strip()
        if not search:
            raise HTTPException(status_code=422, detail="search cannot be blank")
        escaped = search.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        pattern = f"%{escaped}%"
        statement = statement.where(
            or_(
                Transaction.description.ilike(pattern, escape="\\"),
                Transaction.category.ilike(pattern, escape="\\"),
            )
        )
    if category is not None:
        category = category.strip()
        if not category:
            raise HTTPException(status_code=422, detail="category cannot be blank")
        statement = statement.where(func.lower(Transaction.category) == category.lower())
    if transaction_type:
        statement = statement.where(Transaction.transaction_type == transaction_type)
    if date_from is not None:
        statement = statement.where(
            Transaction.occurred_at >= datetime.combine(date_from, time.min, tzinfo=timezone.utc)
        )
    if date_to is not None:
        statement = statement.where(
            Transaction.occurred_at <= datetime.combine(date_to, time.max, tzinfo=timezone.utc)
        )
    if currency:
        statement = statement.where(Transaction.currency == currency)
    return statement


def next_occurrence_date(current: date, frequency: str, anchor_day: int) -> date:
    if frequency == "daily":
        return current + timedelta(days=1)
    if frequency == "weekly":
        return current + timedelta(weeks=1)
    month_index = current.year * 12 + current.month
    next_year, next_month_zero_based = divmod(month_index, 12)
    next_month = next_month_zero_based + 1
    return date(next_year, next_month, min(anchor_day, calendar.monthrange(next_year, next_month)[1]))


def csv_safe_cell(value: str | None) -> str:
    if value is None:
        return ""
    if value.lstrip().startswith(("=", "+", "-", "@")):
        return "'" + value
    return value


def create_app(settings: Settings | None = None, database_url: str | None = None) -> FastAPI:
    settings = settings or Settings()  # type: ignore[call-arg]  # BaseSettings reads required values from env.
    url = database_url or settings.database_url
    connect_args = {"check_same_thread": False} if url.startswith("sqlite") else {}
    engine_options = {}
    if url in {"sqlite://", "sqlite:///:memory:"}:
        engine_options["poolclass"] = StaticPool
    engine = create_engine(url, connect_args=connect_args, **engine_options)
    session_factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        Base.metadata.create_all(bind=engine)
        yield
        engine.dispose()

    app = FastAPI(title="Finance App API", version="1.0.0", lifespan=lifespan)
    app.state.settings = settings
    if settings.otp_provider == "mock":
        app.state.mock_verify_client = MockVerifyClient()
    app.state.session_factory = session_factory
    app.state.engine = engine
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_origin_regex=(
            r"^https?://(?:localhost|127\.0\.0\.1|\[::1\])(?::\d+)?$"
            if settings.app_env == "development"
            else None
        ),
        allow_credentials=True,
        allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type"],
    )


    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/auth/otp/start", status_code=status.HTTP_202_ACCEPTED)
    def start_otp(payload: PhoneRequest, verify: Verify) -> dict[str, str]:
        provider_status = verify.send_code(payload.phone_number)
        return {"status": provider_status, "message": "If eligible, a verification code was sent."}

    @app.post("/auth/otp/verify", response_model=TokenResponse)
    def verify_otp(payload: OTPVerifyRequest, verify: Verify, db: DatabaseSession) -> TokenResponse:
        if verify.check_code(payload.phone_number, payload.code) != "approved":
            raise HTTPException(status_code=400, detail="Phone verification code is invalid or expired")
        user = db.scalar(select(User).where(User.phone_number == payload.phone_number))
        if user is None:
            user = User(phone_number=payload.phone_number)
            db.add(user)
            db.commit()
            db.refresh(user)
        token, expires_in = create_access_token(user.id, settings)
        return TokenResponse(access_token=token, expires_in=expires_in)

    @app.post(
        "/recurring-templates",
        response_model=RecurringTemplateResponse,
        status_code=status.HTTP_201_CREATED,
    )
    def create_recurring_template(
        payload: RecurringTemplateCreate,
        user: CurrentUser,
        db: DatabaseSession,
    ) -> RecurringTemplate:
        template = RecurringTemplate(
            user_id=user.id,
            next_occurrence=payload.start_date,
            **payload.model_dump(),
        )
        db.add(template)
        db.commit()
        db.refresh(template)
        return template

    @app.get("/recurring-templates", response_model=list[RecurringTemplateResponse])
    def list_recurring_templates(user: CurrentUser, db: DatabaseSession) -> list[RecurringTemplate]:
        statement = (
            select(RecurringTemplate)
            .where(RecurringTemplate.user_id == user.id)
            .order_by(RecurringTemplate.id)
        )
        return list(db.scalars(statement).all())

    @app.post("/recurring-templates/materialize-due", response_model=MaterializationResponse)
    def materialize_due_occurrences(
        user: CurrentUser,
        db: DatabaseSession,
        as_of: date | None = None,
        max_occurrences: int = Query(default=100, ge=1, le=500),
    ) -> MaterializationResponse:
        today = datetime.now(timezone.utc).date()
        materialization_date = as_of or today
        if materialization_date > today:
            raise HTTPException(status_code=422, detail="as_of cannot be in the future")

        templates = db.scalars(
            select(RecurringTemplate)
            .where(RecurringTemplate.user_id == user.id)
            .order_by(RecurringTemplate.id)
            .with_for_update()
        ).all()
        materialized: list[MaterializedOccurrence] = []
        try:
            for template in templates:
                while (
                    len(materialized) < max_occurrences
                    and template.next_occurrence <= materialization_date
                    and (template.end_date is None or template.next_occurrence <= template.end_date)
                ):
                    occurrence_date = template.next_occurrence
                    transaction = Transaction(
                        user_id=user.id,
                        amount_minor=template.amount_minor,
                        currency=template.currency,
                        transaction_type=template.transaction_type,
                        description=template.description,
                        category=template.category,
                        occurred_at=datetime.combine(occurrence_date, time.min, tzinfo=timezone.utc),
                    )
                    db.add(transaction)
                    db.flush()
                    db.add(
                        RecurringOccurrence(
                            template_id=template.id,
                            transaction_id=transaction.id,
                            occurrence_date=occurrence_date,
                        )
                    )
                    materialized.append(
                        MaterializedOccurrence(
                            template_id=template.id,
                            occurrence_date=occurrence_date,
                            transaction=TransactionResponse.model_validate(transaction),
                        )
                    )
                    template.next_occurrence = next_occurrence_date(
                        occurrence_date, template.frequency, template.start_date.day
                    )
            db.commit()
        except IntegrityError as exc:
            db.rollback()
            raise HTTPException(
                status_code=409,
                detail="Concurrent materialization detected; retry the request",
            ) from exc

        return MaterializationResponse(
            as_of=materialization_date,
            created_count=len(materialized),
            occurrences=materialized,
        )

    @app.delete("/recurring-templates/{template_id}", status_code=status.HTTP_204_NO_CONTENT)
    def delete_recurring_template(
        template_id: int,
        user: CurrentUser,
        db: DatabaseSession,
    ) -> Response:
        template = db.scalar(
            select(RecurringTemplate).where(
                RecurringTemplate.id == template_id,
                RecurringTemplate.user_id == user.id,
            )
        )
        if template is None:
            raise HTTPException(status_code=404, detail="Recurring template not found")
        db.delete(template)
        db.commit()
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @app.post("/transactions", response_model=TransactionResponse, status_code=status.HTTP_201_CREATED)
    def create_transaction(
        payload: TransactionCreate,
        user: CurrentUser,
        db: DatabaseSession,
    ) -> Transaction:
        transaction = Transaction(user_id=user.id, **payload.model_dump())
        db.add(transaction)
        db.commit()
        db.refresh(transaction)
        return transaction

    @app.get("/transactions", response_model=list[TransactionResponse])
    def list_transactions(
        user: CurrentUser,
        db: DatabaseSession,
        search: str | None = Query(default=None, min_length=1, max_length=100),
        category: str | None = Query(default=None, min_length=1, max_length=80),
        transaction_type: Literal["income", "expense"] | None = None,
        date_from: date | None = None,
        date_to: date | None = None,
        currency: str | None = Query(default=None, pattern=r"^[A-Z]{3}$"),
        limit: int = Query(default=50, ge=1, le=100),
        offset: int = Query(default=0, ge=0),
    ) -> list[Transaction]:
        statement = add_transaction_filters(
            select(Transaction).where(Transaction.user_id == user.id),
            search=search,
            category=category,
            transaction_type=transaction_type,
            date_from=date_from,
            date_to=date_to,
            currency=currency,
        )
        statement = statement.order_by(Transaction.occurred_at.desc(), Transaction.id.desc())
        return list(db.scalars(statement.offset(offset).limit(limit)).all())

    @app.get("/transactions/export.csv")
    def export_transactions_csv(
        user: CurrentUser,
        db: DatabaseSession,
        search: str | None = Query(default=None, min_length=1, max_length=100),
        category: str | None = Query(default=None, min_length=1, max_length=80),
        transaction_type: Literal["income", "expense"] | None = None,
        date_from: date | None = None,
        date_to: date | None = None,
        currency: str | None = Query(default=None, pattern=r"^[A-Z]{3}$"),
    ) -> Response:
        statement = add_transaction_filters(
            select(Transaction).where(Transaction.user_id == user.id),
            search=search,
            category=category,
            transaction_type=transaction_type,
            date_from=date_from,
            date_to=date_to,
            currency=currency,
        )
        statement = statement.order_by(Transaction.occurred_at.desc(), Transaction.id.desc())
        output = StringIO(newline="")
        writer = csv.writer(output)
        writer.writerow(
            ["id", "amount_minor", "currency", "transaction_type", "description", "category", "occurred_at", "created_at"]
        )
        for transaction in db.scalars(statement).all():
            writer.writerow(
                [
                    transaction.id,
                    transaction.amount_minor,
                    transaction.currency,
                    transaction.transaction_type,
                    csv_safe_cell(transaction.description),
                    csv_safe_cell(transaction.category),
                    transaction.occurred_at.isoformat(),
                    transaction.created_at.isoformat(),
                ]
            )
        return Response(
            content=output.getvalue(),
            media_type="text/csv; charset=utf-8",
            headers={"Content-Disposition": "attachment; filename=transactions.csv"},
        )

    @app.get("/transactions/summary", response_model=TransactionSummaryResponse)
    def transaction_summary(
        user: CurrentUser,
        db: DatabaseSession,
        currency: str = Query(..., min_length=3, max_length=3, pattern=r"^[A-Z]{3}$"),
    ) -> TransactionSummaryResponse:
        income_total = func.coalesce(
            func.sum(
                case(
                    (Transaction.transaction_type == "income", Transaction.amount_minor),
                    else_=0,
                )
            ),
            0,
        )
        expense_total = func.coalesce(
            func.sum(
                case(
                    (Transaction.transaction_type == "expense", Transaction.amount_minor),
                    else_=0,
                )
            ),
            0,
        )
        statement = (
            select(income_total.label("income_minor"), expense_total.label("expense_minor"))
            .where(Transaction.user_id == user.id, Transaction.currency == currency)
        )
        income_minor, expense_minor = db.execute(statement).one()
        return TransactionSummaryResponse(
            balance_minor=income_minor - expense_minor,
            income_minor=income_minor,
            expense_minor=expense_minor,
            currency=currency,
        )

    @app.get("/transactions/{transaction_id}", response_model=TransactionResponse)
    def get_transaction(
        transaction_id: int,
        user: CurrentUser,
        db: DatabaseSession,
    ) -> Transaction:
        transaction = db.get(Transaction, transaction_id)
        if transaction is None or transaction.user_id != user.id:
            raise HTTPException(status_code=404, detail="Transaction not found")
        return transaction

    @app.patch("/transactions/{transaction_id}", response_model=TransactionResponse)
    def update_transaction(
        transaction_id: int,
        payload: TransactionUpdate,
        user: CurrentUser,
        db: DatabaseSession,
    ) -> Transaction:
        transaction = db.get(Transaction, transaction_id)
        if transaction is None or transaction.user_id != user.id:
            raise HTTPException(status_code=404, detail="Transaction not found")
        updates = payload.model_dump(exclude_unset=True)
        for field, value in updates.items():
            setattr(transaction, field, value)
        db.commit()
        db.refresh(transaction)
        return transaction

    @app.delete("/transactions/{transaction_id}", status_code=status.HTTP_204_NO_CONTENT)
    def delete_transaction(
        transaction_id: int,
        user: CurrentUser,
        db: DatabaseSession,
    ) -> Response:
        transaction = db.get(Transaction, transaction_id)
        if transaction is None or transaction.user_id != user.id:
            raise HTTPException(status_code=404, detail="Transaction not found")
        db.delete(transaction)
        db.commit()
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    return app


app = create_app()
