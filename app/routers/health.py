from fastapi import APIRouter, HTTPException
from sqlalchemy import text

from app.db.session import AsyncSessionLocal
from app.services.redis import get_redis

router = APIRouter()


@router.get("/health", include_in_schema=False)
async def health():
    errors = []

    try:
        async with AsyncSessionLocal() as session:
            await session.execute(text("SELECT 1"))
    except Exception as e:
        errors.append(f"db: {e}")

    try:
        await get_redis().ping()
    except Exception as e:
        errors.append(f"redis: {e}")

    if errors:
        raise HTTPException(status_code=503, detail={"status": "unhealthy", "errors": errors})

    return {"status": "ok"}
