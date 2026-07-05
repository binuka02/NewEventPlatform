FROM apache/superset:latest

USER root

RUN pip install clickhouse-connect --break-system-packages || \
    pip install clickhouse-connect || \
    /app/.venv/bin/python -m pip install clickhouse-connect || \
    python -m pip install clickhouse-connect

# Verify installation
RUN python -c "import clickhouse_connect; print('clickhouse_connect installed successfully!')" || \
    /app/.venv/bin/python -c "import sys; sys.path.insert(0, '/usr/local/lib/python3.10/site-packages'); import clickhouse_connect; print('found in system!')"

USER superset