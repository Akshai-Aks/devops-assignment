import pytest
from unittest.mock import patch
from app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


def test_index(client):
    response = client.get("/")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "ok"


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "healthy"


def test_db_check_success(client):
    with patch("app.get_db_connection") as mock_conn:
        mock_conn.return_value.__enter__ = lambda s: s
        mock_conn.return_value.close = lambda: None
        response = client.get("/db")
    assert response.status_code == 200
    data = response.get_json()
    assert data["db"] == "connected"


def test_db_check_failure(client):
    with patch("app.get_db_connection", side_effect=Exception("connection refused")):
        response = client.get("/db")
    assert response.status_code == 500
    data = response.get_json()
    assert data["status"] == "error"
