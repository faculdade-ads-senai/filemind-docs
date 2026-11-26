# Sobe o FileMind local: Postgres+pgvector, Ollama, backend, RAG e front.
# Copie esta pasta para <pasta-dos-repos>\.ambiente (ao lado de filemind-backend, filemind-rag e filemind-frontend).
# Uso: powershell -ExecutionPolicy Bypass -File <pasta-dos-repos>\.ambiente\subir-tudo.ps1
$ErrorActionPreference = 'Stop'
$amb = $PSScriptRoot
$base = Split-Path $amb -Parent

# 1. Banco (PostgreSQL 16 + pgvector, binarios em .ambiente\postgres)
$pgctl = Join-Path $amb 'postgres\bin\pg_ctl.exe'
& $pgctl -D (Join-Path $amb 'pgdata') status *> $null
if ($LASTEXITCODE -ne 0) {
    & $pgctl -D (Join-Path $amb 'pgdata') -l (Join-Path $amb 'postgres.log') -o '-p 5432 -c listen_addresses=localhost' -w start
}

# 2. Ollama (bge-m3 para embeddings, qwen2.5:3b para o chat)
if (-not (Get-Process -Name 'ollama' -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath "$env:LOCALAPPDATA\Programs\Ollama\ollama app.exe"
}

# 3. Backend (porta 8080; aplica as migrations Flyway ao subir)
$envBack = "`$env:DB_URL='jdbc:postgresql://localhost:5432/filemind'; `$env:DB_USER='filemind'; `$env:DB_PASSWORD='filemind'; `$env:FILEMIND_ARMAZENAMENTO='local'; `$env:FILEMIND_ARMAZENAMENTO_DIR='$amb\armazenamento'"
Start-Process powershell -WorkingDirectory (Join-Path $base 'filemind-backend') -ArgumentList '-NoExit', '-Command', "`$host.UI.RawUI.WindowTitle='FileMind backend'; $envBack; .\mvnw.cmd spring-boot:run"

# 4. RAG (porta 8001; espera o backend criar as tabelas)
$envRag = "`$env:DATABASE_URL='postgresql://filemind:filemind@localhost:5432/filemind'; `$env:FILEMIND_ARMAZENAMENTO='local'; `$env:FILEMIND_ARMAZENAMENTO_DIR='$amb\armazenamento'"
Start-Process powershell -WorkingDirectory (Join-Path $base 'filemind-rag') -ArgumentList '-NoExit', '-Command', "`$host.UI.RawUI.WindowTitle='FileMind RAG'; $envRag; Start-Sleep 25; .\.venv\Scripts\python.exe servidor_local.py"

# 5. Front (porta 5173)
Start-Process powershell -WorkingDirectory (Join-Path $base 'filemind-frontend') -ArgumentList '-NoExit', '-Command', "`$host.UI.RawUI.WindowTitle='FileMind front'; npm run dev"

Write-Host 'Subindo. Abra http://localhost:5173 quando o backend mostrar "Started FilemindApplication".'
