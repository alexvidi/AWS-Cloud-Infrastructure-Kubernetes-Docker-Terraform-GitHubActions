# -----------------------------------------------------------------------------
# FastAPI API tests
#
# Goal:
# - Validate that the /health endpoint returns 200 and the expected payload.
# - Validate that /quote returns 200 and exposes the synthetic quote contract.
# - Validate that supported symbols return stable synthetic quotes.
# -----------------------------------------------------------------------------

from datetime import datetime

from fastapi.testclient import TestClient

from app.main import app


# Test client used across test cases.
client = TestClient(app)


def assert_quote_payload(payload: dict, expected_symbol: str):
    assert payload["symbol"] == expected_symbol
    assert payload["currency"] == "USD"
    assert isinstance(payload["price"], int)
    assert payload["price"] > 0
    assert payload["source"] == "synthetic"
    assert datetime.fromisoformat(payload["generated_at"]).tzinfo is not None


def test_health_returns_ok():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_quote_returns_synthetic_market_quote():
    response = client.get("/quote", params={"symbol": "btc"})
    assert response.status_code == 200
    data = response.json()
    assert data["symbol"] == "BTC"
    assert_quote_payload(data, "BTC")


def test_quote_returns_synthetic_market_quote_for_another_symbol():
    response = client.get("/quote", params={"symbol": "ETH"})
    assert response.status_code == 200
    assert_quote_payload(response.json(), "ETH")


def test_quote_rejects_unsupported_symbol():
    response = client.get("/quote", params={"symbol": "DOGE"})
    assert response.status_code == 400
    data = response.json()
    assert data["detail"]["error"] == "unsupported_symbol"
    assert data["detail"]["supported_symbols"] == ["AAPL", "BTC", "ETH", "SOL"]


def test_metrics_endpoint_exposes_prometheus():
    response = client.get("/metrics")
    assert response.status_code == 200
    # Basic sanity: metrics output should contain a known Prometheus metric name.
    assert "http_requests_total" in response.text or "http_request_duration_seconds" in response.text
