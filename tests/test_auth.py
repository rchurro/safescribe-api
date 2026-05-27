import pytest

from app.services.auth import create_access_token


@pytest.mark.asyncio
async def test_register_success(client):
    resp = await client.post("/auth/register", json={"email": "alice@example.com", "password": "secret123"})
    assert resp.status_code == 201
    data = resp.json()
    assert data["email"] == "alice@example.com"
    assert data["is_paid"] is False


@pytest.mark.asyncio
async def test_register_duplicate_email(client):
    await client.post("/auth/register", json={"email": "bob@example.com", "password": "pass"})
    resp = await client.post("/auth/register", json={"email": "bob@example.com", "password": "pass"})
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_login_success(client, mock_redis):
    await client.post("/auth/register", json={"email": "carol@example.com", "password": "mypassword"})
    mock_redis["store"].return_value = None
    resp = await client.post("/auth/login", json={"email": "carol@example.com", "password": "mypassword"})
    assert resp.status_code == 200
    data = resp.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"


@pytest.mark.asyncio
async def test_login_wrong_password(client):
    await client.post("/auth/register", json={"email": "dave@example.com", "password": "correct"})
    resp = await client.post("/auth/login", json={"email": "dave@example.com", "password": "wrong"})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_refresh_success(client, mock_redis):
    mock_redis["get"].return_value = 99
    mock_redis["store"].return_value = None
    mock_redis["delete"].return_value = None
    resp = await client.post("/auth/refresh", json={"refresh_token": "some-valid-token"})
    assert resp.status_code == 200
    assert "access_token" in resp.json()


@pytest.mark.asyncio
async def test_refresh_invalid_token(client, mock_redis):
    mock_redis["get"].return_value = None
    resp = await client.post("/auth/refresh", json={"refresh_token": "bad-token"})
    assert resp.status_code == 401
