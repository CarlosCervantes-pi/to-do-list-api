import os
os.environ["TESTING"] = "1"
os.environ["APP_VERSION"] = "v1.2.3-test"

from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient
from src.main import app

client = TestClient(app)


def test_get_version():
    response = client.get("/version")
    assert response.status_code == 200
    assert response.json() == {"version": "v1.2.3-test"}


@patch("src.main.get_db_connection")
def test_health_ok(mock_conn):
    mock_cursor = MagicMock()
    mock_conn.return_value.cursor.return_value.__enter__.return_value = mock_cursor

    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "OK"
    assert data["version"] == "v1.2.3-test"
    assert "timestamp" in data


@patch("src.main.put_custom_metric")
@patch("src.main.get_db_connection")
def test_create_and_list_tasks(mock_conn, mock_metric):
    mock_cursor = MagicMock()
    mock_cursor.fetchone.return_value = {"id": 1, "title": "Estudiar nube", "done": False}
    mock_cursor.fetchall.return_value = [{"id": 1, "title": "Estudiar nube", "done": False}]
    mock_conn.return_value.cursor.return_value.__enter__.return_value = mock_cursor

    post_res = client.post("/tasks", json={"title": "Estudiar nube", "done": False})
    assert post_res.status_code == 201
    assert post_res.json()["title"] == "Estudiar nube"

    get_res = client.get("/tasks")
    assert get_res.status_code == 200
    assert len(get_res.json()) == 1


@patch("src.main.put_custom_metric")
@patch("src.main.get_db_connection")
def test_health_fail_emits_metric(mock_conn, mock_metric):
    mock_conn.side_effect = Exception("Connection refused")

    response = client.get("/health")
    assert response.status_code == 503
    mock_metric.assert_called_with("DBConnectionErrors", 1.0)
