import pytest
from app import app, db_conn

@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client

def test_health_check(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "healthy"}

def test_valid_user_search(client):
    response = client.get("/api/users/search?username=alice")
    assert response.status_code == 200
    data = response.get_json()
    assert len(data["users"]) == 1
    assert data["users"][0]["username"] == "alice"
    assert data["users"][0]["email"] == "alice@example.com"

def test_nonexistent_user_search(client):
    response = client.get("/api/users/search?username=nobody")
    assert response.status_code == 200
    data = response.get_json()
    assert len(data["users"]) == 0

def test_sql_injection_defense(client):
    """
    Test verifying that SQL injection payloads do not leak unauthorized records
    or cause database syntax errors.
    """
    # Classic SQL injection attempt to dump all users
    response = client.get("/api/users/search?username=' OR '1'='1")
    assert response.status_code == 200
    data = response.get_json()
    # If parameterized properly, searching for literal username "' OR '1'='1" returns 0 users.
    # If vulnerable, it returns all 3 users.
    assert len(data["users"]) == 0
