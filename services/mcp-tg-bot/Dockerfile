FROM python:3.12-slim

# Install curl for the docker healthcheck (the image's slim base lacks it).
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pyproject.toml ./
RUN pip install --no-cache-dir -e .

COPY server.py ./

EXPOSE 8818

# CMD does NOT hardcode --port/--host so MCP_HTTP_PORT and MCP_HTTP_HOST
# env vars (read at module load in server.py) actually take effect. server.py
# defaults: port=8818, host=127.0.0.1 (latter rebound to 0.0.0.0 by env in
# port-mapped non-host-network setups; production uses network_mode: host
# and keeps the 127.0.0.1 default — plan §S.2 LAN-exposure mitigation).
CMD ["python", "-m", "server", "--transport", "http"]
