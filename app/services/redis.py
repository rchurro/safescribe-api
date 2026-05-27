from typing import Optional

import redis.asyncio as aioredis

from app.config import get_settings

settings = get_settings()

_redis: Optional[aioredis.Redis] = None


def get_redis() -> aioredis.Redis:
    global _redis
    if _redis is None:
        _redis = aioredis.from_url(settings.redis_url, decode_responses=True)
    return _redis


def _key(token: str) -> str:
    return f"refresh:{token}"


async def store_refresh_token(user_id: int, token: str, expire_days: int) -> None:
    await get_redis().setex(_key(token), expire_days * 86400, str(user_id))


async def get_refresh_token_user_id(token: str) -> Optional[int]:
    value = await get_redis().get(_key(token))
    return int(value) if value else None


async def delete_refresh_token(token: str) -> None:
    await get_redis().delete(_key(token))
