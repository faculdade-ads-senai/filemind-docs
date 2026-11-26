# FileMind: contrato do ambiente local (apresentacao de 26/11/2026)

Objetivo: demo local completa. Usuario cria conta, faz login, envia um `.md`, o RAG indexa
(chunks + embeddings no pgvector), o usuario pergunta e recebe resposta com as fontes.
Nada de AWS agora (a conta foi perdida). Na semana que vem o RAG vira Lambda, entao o codigo
do RAG ja nasce com handlers no formato Lambda, mas so o modo local precisa funcionar hoje.

Pastas (irmas): `C:/vscode/faculdade/filemind/`
- `filemind-backend` (Java 21, Spring Boot 4, porta 8080)
- `filemind-rag` (Python, porta 8001) - repositorio novo
- `filemind-frontend` (React 19 + Vite 7 + Tailwind 4, porta 5173)
- `filemind-documentacao/rag/ARQUITETURA-RAG-MVP.md` - regras do RAG (chunking, SQL, prompt). Siga-o,
  exceto onde este contrato diz outra coisa (aqui o RAG roda fora do backend).
- `.ambiente/armazenamento` - pasta local que substitui o S3 (objeto = pasta + "/" + s3_key)

## Banco (PostgreSQL 16 + pgvector, local)
- JDBC: `jdbc:postgresql://localhost:5432/filemind`, usuario `filemind`, senha `filemind`
- Python: `postgresql://filemind:filemind@localhost:5432/filemind`
- Quem cria/migra o schema e o backend (Flyway V1..V3). O RAG so le/escreve.
- Tabelas: `tb_usuarios`, `tb_arquivos` (status_rag ENVIADO|PROCESSANDO|PROCESSADO|ERRO,
  embedding_provedor/modelo/versao/dimensao, s3_key, erro_processamento), `tb_chunks_arquivo`
  (arquivo_id, indice, conteudo, embedding vector(1024), metadados jsonb). Restricao: status
  PROCESSADO exige provedor, modelo, versao nao nulos e dimensao = 1024.

## Backend (http://localhost:8080) - o front chama via proxy `/api` -> `http://localhost:8080`
Ja existem:
- `POST /usuarios` {usuario, nome, senha} -> 201 {idUsuario, usuario, nome}. `usuario` = e-mail.
  Senha: 8-72, maiuscula, minuscula, numero e especial (@#$%^&+=!). Erros de validacao -> 400.
- `GET /arquivos/usuarios/{idUsuario}` -> lista de ArquivoResponseDTO
  {idArquivo, nomeArquivo, proprietarioArquivo, caminhoVirtual, extensaoArquivo, tipoMime,
   tamanhoBytes, statusRag, metadadosArquivo, criadoEm}
- `POST /arquivos` multipart (`idUsuario`, `arquivo`) -> 201 ArquivoResponseDTO, statusRag ENVIADO
Novos:
- `POST /auth/login` {usuario, senha} -> 200 {idUsuario, usuario, nome}; senha errada ou usuario
  inexistente -> 401 {"mensagem": "Usuario ou senha invalidos"} (mesma mensagem nos dois casos)
- `GET /arquivos/{idArquivo}/conteudo?idUsuario=X` -> 200 text/markdown; charset=UTF-8 (conteudo do
  arquivo); 404 se nao existe ou nao e do usuario
- `DELETE /arquivos/{idArquivo}?idUsuario=X` -> 204 (apaga objeto e linha; chunks caem em cascata);
  404 se nao existe ou nao e do usuario
- Armazenamento: `filemind.armazenamento.tipo=${FILEMIND_ARMAZENAMENTO:local}` (local|s3) e
  `filemind.armazenamento.dir=${FILEMIND_ARMAZENAMENTO_DIR:../.ambiente/armazenamento}`.
  local grava em dir/s3_key (cria subpastas). s3 mantem o S3Service atual.

## RAG (http://localhost:8001) - o front chama via proxy `/rag` -> `http://localhost:8001`
- `GET /saude` -> {"status":"ok","embedding":{"provedor","modelo"},"chat":{"provedor","modelo"}}
- `POST /perguntar` {usuarioId, pergunta, arquivoId?} -> 200
  {"resposta": "...", "fontes": [{"arquivoId", "nomeArquivo", "indiceChunk", "trecho", "similaridade"}]}
  400 se faltar usuarioId/pergunta. Sem chunks encontrados: resposta dizendo que nao achou nada
  nos arquivos do usuario e fontes [] (sem chamar o modelo de chat).
- `POST /indexar/{arquivoId}` -> reindexa na hora -> {"arquivoId", "statusRag", "chunks"}
- Worker local: a cada 3 s pega arquivos com status_rag = 'ENVIADO' (mais antigo primeiro) e indexa.
- Provedores locais (Ollama em http://localhost:11434):
  - embedding `bge-m3` via `POST /api/embed` {"model","input":[...]} -> {"embeddings": [[1024 floats]]}
  - chat `qwen2.5:3b` via `POST /api/chat` {"model","messages","stream":false,"options":{"temperature":0.2}}
  - embedding_versao = digest do modelo em `GET /api/tags`
- Variaveis: DATABASE_URL, OLLAMA_URL, EMBEDDING_MODEL, CHAT_MODEL, RAG_TOP_K=5,
  RAG_CHUNK_MAX_CHARS=2000, RAG_CHUNK_OVERLAP_CHARS=200, FILEMIND_ARMAZENAMENTO=local|s3,
  FILEMIND_ARMAZENAMENTO_DIR=../.ambiente/armazenamento, RAG_PORTA=8001
