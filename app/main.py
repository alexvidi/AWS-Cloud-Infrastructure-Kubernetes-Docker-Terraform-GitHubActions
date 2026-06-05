"""
Simple FastAPI application that exposes three endpoints:

- GET /health   -> Basic health check for Kubernetes and monitoring.
- GET /quote    -> Returns a synthetic market quote for a supported symbol.
- GET /metrics  -> Exposes Prometheus metrics for scraping.

This file focuses only on the HTTP API layer.
The business logic is intentionally lightweight and honest: the API returns
synthetic quotes for a small symbol catalog so the repository can focus on
cloud delivery and runtime operations rather than fake machine learning.
"""

from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException

# Prometheus metrics instrumentator for FastAPI.
from prometheus_fastapi_instrumentator import Instrumentator


# Small catalog of supported symbols.
# Each symbol maps to a stable synthetic quote so the API can return a realistic
# structure without pretending to be a real-time market data service.
SUPPORTED_QUOTES = {
    "BTC": {"currency": "USD", "price": 58_007},
    "ETH": {"currency": "USD", "price": 3_198},
    "SOL": {"currency": "USD", "price": 141},
    "AAPL": {"currency": "USD", "price": 193},
}

# Create the main FastAPI application instance.
# This "app" object is what Uvicorn will run inside the Docker container.
app = FastAPI(
    title="Market Quote API",
    description=(
        "Synthetic market quote API used to demonstrate cloud-native delivery, "
        "security, and operations on Azure."
    ),
    version="1.1.0",
)

# Expose Prometheus metrics at /metrics (not part of the OpenAPI schema).
Instrumentator().instrument(app).expose(app, include_in_schema=False, endpoint="/metrics")


@app.get("/health")
def health_check():
    """
    Health-check endpoint.

    Purpose:
    - Allow Kubernetes (and other tools) to verify that the application is running.
    - If this endpoint returns {"status": "ok"}, we consider the service "healthy".

    Returns
    -------
    dict
        A very small JSON payload with a static status message.
    """
    return {"status": "ok"}


def build_synthetic_quote(symbol: str) -> dict:
    """
    Build a synthetic quote payload for a supported symbol.

    The returned price is not sourced from an external provider. Instead we
    use a small in-memory catalog of explicit synthetic quotes. That keeps the
    API honest, stable, and easy to understand while still looking like a real
    service contract.

    Parameters
    ----------
    symbol : str
        Asset ticker sent by the client (for example: "BTC", "ETH", "AAPL"...).

    Returns
    -------
    dict
        A JSON object with:
        - "symbol": the normalized asset ticker.
        - "currency": quote currency.
        - "price": synthetic market price from the local catalog.
        - "source": data origin marker ("synthetic").
        - "generated_at": UTC timestamp for the generated quote.
    """
    normalized_symbol = symbol.strip().upper()
    quote_definition = SUPPORTED_QUOTES.get(normalized_symbol)

    if quote_definition is None:
        raise HTTPException(
            status_code=400,
            detail={
                "error": "unsupported_symbol",
                "supported_symbols": sorted(SUPPORTED_QUOTES.keys()),
            },
        )

    # Build the response payload returned to the client.
    return {
        "symbol": normalized_symbol,
        "currency": quote_definition["currency"],
        "price": quote_definition["price"],
        "source": "synthetic",
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/quote")
def get_quote(symbol: str):
    """
    Synthetic quote endpoint.

    This is the primary business endpoint exposed by the application.
    It returns a lightweight but well-structured market quote payload for a
    supported symbol.
    """
    return build_synthetic_quote(symbol)

