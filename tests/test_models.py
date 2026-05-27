import pytest

from app.constants.webllm import ALL_MODEL_IDS, FREE_MODEL_ID
from app.services.auth import create_access_token


@pytest.mark.asyncio
async def test_list_models_anonymous(client):
    resp = await client.get("/models")
    assert resp.status_code == 200
    data = resp.json()
    assert data["models"] == [FREE_MODEL_ID]
    assert data["is_paid"] is False


@pytest.mark.asyncio
async def test_list_models_free_user(client, db):
    from app.models.user import User
    from app.services.auth import hash_password

    user = User(email="free@example.com", hashed_password=hash_password("pw"), is_paid=False)
    db.add(user)
    await db.commit()
    await db.refresh(user)

    token = create_access_token({"sub": str(user.id)})
    resp = await client.get("/models", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["models"] == [FREE_MODEL_ID]
    assert data["is_paid"] is False


@pytest.mark.asyncio
async def test_list_models_paid_user(client, db):
    from app.models.user import User
    from app.services.auth import hash_password

    user = User(email="paid@example.com", hashed_password=hash_password("pw"), is_paid=True)
    db.add(user)
    await db.commit()
    await db.refresh(user)

    token = create_access_token({"sub": str(user.id)})
    resp = await client.get("/models", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["models"] == ALL_MODEL_IDS
    assert data["is_paid"] is True
    assert len(data["models"]) == 163
