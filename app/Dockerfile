# -----------------------------------------------------------------------------
# Dockerfile for the Market Quote API
#
# Goal:
# - Build a lightweight Python image that runs a small FastAPI application.
# - Install only the required dependencies.
# - Run the app as a non-root user for better security.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# BASE IMAGE
# -----------------------------------------------------------------------------
# We use an official Python image as our base.
# "slim" means it is a lighter version with fewer preinstalled packages.
FROM python:3.10-slim

# Set the working directory inside the container.
# All subsequent commands will run from /app.
WORKDIR /app

# Refresh security patches from the base Debian image before installing Python
# dependencies so the runtime starts from the latest available package set.
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# DEPENDENCIES INSTALLATION
# -----------------------------------------------------------------------------
# Copy the dependencies file into the image.
# We only copy requirements.txt here to keep Docker layer caching efficient.
COPY requirements.txt .

# Install Python dependencies without keeping pip cache to reduce image size.
RUN pip install --no-cache-dir --upgrade pip setuptools wheel \
    && pip install --no-cache-dir -r requirements.txt

# -----------------------------------------------------------------------------
# RUNTIME CONFIGURATION
# -----------------------------------------------------------------------------
# Create a dedicated non-root user called "appuser".
# Running as non-root is a common security best practice.
RUN adduser --disabled-password --gecos "" appuser

# Copy the rest of the application code into the image.
# This includes main.py and any other project files.
COPY . .

# Give ownership of all files under /app to "appuser".
# This ensures the non-root user can read and execute the code.
RUN chown -R appuser:appuser /app

# Switch to the non-root user for the rest of the container lifecycle.
USER appuser

# -----------------------------------------------------------------------------
# NETWORK CONFIGURATION
# -----------------------------------------------------------------------------
# Document that the application listens on port 8000 inside the container.
# (Kubernetes will later map this internal port to an external one via a Service.)
EXPOSE 8000

# -----------------------------------------------------------------------------
# APPLICATION STARTUP COMMAND
# -----------------------------------------------------------------------------
# Start the FastAPI application using Uvicorn.
# "main:app" means:
#   - main → the Python module name (main.py).
#   - app  → the FastAPI instance created in that file.
# --host 0.0.0.0 → listen on all network interfaces inside the container.
# --port 8000    → listen on port 8000 (the same we exposed above).
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
