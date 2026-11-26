# Para o Postgres local. Backend, RAG e front: feche as janelas deles (ou Ctrl+C).
& (Join-Path $PSScriptRoot 'postgres\bin\pg_ctl.exe') -D (Join-Path $PSScriptRoot 'pgdata') stop
