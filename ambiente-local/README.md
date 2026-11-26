# Ambiente local do FileMind

Roda o MVP inteiro numa máquina Windows, sem nuvem: PostgreSQL com pgvector, Ollama, backend, RAG e front. Foi o ambiente usado na apresentação do PA III (26/11/2026).

## Estrutura esperada

```
<pasta-dos-repos>/
  filemind-backend/
  filemind-frontend/
  filemind-rag/
  .ambiente/          <- copia desta pasta (ambiente-local)
    postgres/         <- binarios do PostgreSQL 16 + pgvector (passo 2)
    pgdata/           <- dados do banco (criado pelo initdb)
    armazenamento/    <- substitui o S3: arquivos enviados pelos usuarios
```

## Preparar (uma vez)

1. Instale Java 21, Node 20+, Python 3.12+ e o [Ollama](https://ollama.com).
2. PostgreSQL 16 com pgvector. Serve qualquer instalação. Na demo foram usados os binários do pacote Python `pgserver`, que já traz o pgvector 0.6.2 e dispensa instalador:
   ```powershell
   pip download pgserver --no-deps -d .ambiente\download
   # abra o .whl como zip e copie o conteudo de pgserver\pginstall\ para .ambiente\postgres\
   .ambiente\postgres\bin\initdb.exe -D .ambiente\pgdata -U filemind -W -E UTF8 --locale=C   # senha: filemind
   .ambiente\postgres\bin\pg_ctl.exe -D .ambiente\pgdata -l .ambiente\postgres.log -o "-p 5432 -c listen_addresses=localhost" -w start
   .ambiente\postgres\bin\createdb.exe -h localhost -U filemind filemind
   ```
   As tabelas e a extensão `vector` são criadas pelo backend (Flyway V1 a V3) na primeira vez que ele sobe.
3. Modelos do Ollama: `ollama pull bge-m3` e `ollama pull qwen2.5:3b`.
4. RAG: na pasta `filemind-rag`, rode `python -m venv .venv` e depois `.\.venv\Scripts\python.exe -m pip install -r requirements.txt`.
5. Front: `npm install` na pasta `filemind-frontend`.

## Subir e parar

```powershell
powershell -ExecutionPolicy Bypass -File <pasta-dos-repos>\.ambiente\subir-tudo.ps1
```

O script sobe o banco e o Ollama e abre três janelas: backend (8080), RAG (8001) e front (5173). Está tudo no ar quando `http://localhost:5173/rag/saude` responde `"status": "ok"`.

Para parar, feche as três janelas e rode `parar-banco.ps1`.

## Arquivos desta pasta

| Arquivo | Para que serve |
| --- | --- |
| `CONTRATO-LOCAL.md` | Contrato entre backend, RAG e front: rotas, campos, tabelas e variáveis. Foi a especificação usada para implementar as três partes. |
| `subir-tudo.ps1` / `parar-banco.ps1` | Sobem e param o ambiente. |
| `exemplos/` | Arquivos Markdown para a demonstração. |

## Tempo de resposta

Na CPU, sem GPU, cada resposta do chat leva cerca de 50 s, e a primeira depois de um tempo parado demora mais. Antes de uma apresentação, faça uma pergunta para aquecer o modelo.
