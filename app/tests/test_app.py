import pytest
from unittest.mock import patch, MagicMock
from app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


def test_index(client):
    response = client.get("/")
    assert response.status_code == 200
    assert b"DevOps Assignment App" in response.data


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json()["status"] == "healthy"


def test_db_check_success(client):
    with patch("app.get_db_connection") as mock:
        mock.return_value.close = MagicMock()
        response = client.get("/db")
    assert response.status_code == 200
    assert response.get_json()["db"] == "connected"


def test_db_check_failure(client):
    with patch("app.get_db_connection", side_effect=Exception("connection refused")):
        response = client.get("/db")
    assert response.status_code == 500
    assert response.get_json()["status"] == "error"


def test_create_user_success(client):
    mock_user = {"id": 1, "name": "Alice", "email": "alice@example.com", "created_at": "2024-01-01"}
    mock_conn = MagicMock()
    mock_cur = MagicMock()
    mock_cur.fetchone.return_value = mock_user
    mock_conn.cursor.return_value = mock_cur

    with patch("app.get_db_connection", return_value=mock_conn):
        response = client.post("/users", json={"name": "Alice", "email": "alice@example.com"})

    assert response.status_code == 201
    assert response.get_json()["user"]["email"] == "alice@example.com"


def test_create_user_missing_fields(client):
    response = client.post("/users", json={"name": "Alice"})
    assert response.status_code == 400
    assert "required" in response.get_json()["error"]


def test_create_user_no_body(client):
    response = client.post("/users", data="", content_type="application/json")
    assert response.status_code == 400


def test_get_users_success(client):
    mock_users = [
        {"id": 1, "name": "Alice", "email": "alice@example.com", "created_at": "2024-01-01"},
        {"id": 2, "name": "Bob",   "email": "bob@example.com",   "created_at": "2024-01-02"},
    ]
    mock_conn = MagicMock()
    mock_cur = MagicMock()
    mock_cur.fetchall.return_value = mock_users
    mock_conn.cursor.return_value = mock_cur

    with patch("app.get_db_connection", return_value=mock_conn):
        response = client.get("/users")

    assert response.status_code == 200
    assert len(response.get_json()["users"]) == 2


def test_get_users_db_error(client):
    with patch("app.get_db_connection", side_effect=Exception("db down")):
        response = client.get("/users")
    assert response.status_code == 500
