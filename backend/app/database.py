from collections.abc import Generator

from fastapi import Request
from sqlalchemy.orm import Session, sessionmaker


def get_db(request: Request) -> Generator[Session, None, None]:
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    with session_factory() as session:
        yield session
