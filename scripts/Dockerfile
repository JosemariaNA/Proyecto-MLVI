# Imagen del ejecutor dbt que levanta ADF como Azure Container Instance.
# Se mantiene minima a proposito: cada MB extra es tiempo de arranque
# que se paga en cada microlote.
FROM python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    DBT_PROFILES_DIR=/app/.dbt

# Driver ODBC 18 de Microsoft: requisito de dbt-synapse.
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl gnupg apt-transport-https ca-certificates unixodbc-dev g++ \
 && curl -sSL https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" \
        > /etc/apt/sources.list.d/mssql-release.list \
 && apt-get update \
 && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 \
 && apt-get purge -y curl gnupg \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
        "dbt-core~=1.8" \
       "dbt-synapse~=1.8" \
        "dbt-sqlserver~=1.8"

WORKDIR /app
COPY dbt/ /app/
RUN dbt deps

ENTRYPOINT []
CMD ["dbt", "build", "--target", "prod"]
