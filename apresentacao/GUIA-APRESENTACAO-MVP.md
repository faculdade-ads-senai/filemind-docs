# FileMind: guia da apresentação do MVP (PA III, 26/11/2026)

Divisão da fala: **Yuri** apresenta o backend, **Victor** o frontend e **Luís** o RAG. A demo roda localmente (ver [ambiente-local](../ambiente-local/README.md)).

## O produto em uma frase

O usuário guarda seus arquivos Markdown e faz perguntas sobre eles em linguagem natural. A resposta usa só o conteúdo dos arquivos dele e mostra de quais trechos veio.

## Arquitetura da demo

```
Navegador (React, :5173)
  |-- /api --> Backend Java/Spring (:8080) --> PostgreSQL 16 + pgvector (:5432)
  |                                       \--> Armazenamento (pasta local; S3 na nuvem)
  \-- /rag --> RAG Python (:8001) ---------> PostgreSQL 16 + pgvector
                                     \-----> Ollama (:11434): bge-m3 (embeddings), qwen2.5:3b (resposta)
```

Fluxo completo:

1. **Envio**: o front manda o `.md` ao backend. O backend grava o arquivo no armazenamento e a linha em `tb_arquivos` com `status_rag = ENVIADO`.
2. **Indexação**: a cada 3 s o worker do RAG pega o arquivo `ENVIADO` mais antigo e o marca `PROCESSANDO`. Depois lê o arquivo, divide em trechos (chunks), gera um vetor de 1.024 números para cada trecho e grava em `tb_chunks_arquivo`. No fim o status vira `PROCESSADO`, ou `ERRO` com a mensagem. O front mostra esses status como Na fila, Indexando, Pronto e Erro.
3. **Pergunta**: o RAG gera o vetor da pergunta e busca os 5 trechos mais parecidos, só entre os arquivos do usuário (ou só no arquivo escolhido). Em seguida manda trechos e pergunta ao modelo de linguagem com a instrução de responder apenas com base nesse contexto, e devolve a resposta com as fontes.

## Backend (Yuri)

Repositório: `filemind-backend`. Mudanças da demo no [PR #6](https://github.com/faculdade-ads-senai/filemind-backend/pull/6).

- **Stack**: Java 21, Spring Boot 4.1.1, Spring Data JPA, Flyway, PostgreSQL 16 + pgvector, `spring-security-crypto` (só o BCrypt, sem o Spring Security completo).
- **Módulos**: `usuarios` (cadastro, login, atualização) e `arquivos` (envio, lista, conteúdo, exclusão). O módulo `rag` mapeia a tabela de chunks e tem uma busca vetorial testada. Na demo, quem indexa e busca é o serviço RAG.
- **Endpoints principais**:

| Método | Rota | O que faz |
| --- | --- | --- |
| POST | `/usuarios` | Cadastro (senha forte obrigatória, guardada como hash BCrypt) |
| POST | `/auth/login` | Login: `401` com a mesma mensagem para e-mail inexistente e senha errada |
| GET | `/arquivos/usuarios/{id}` | Arquivos do usuário, com o status da indexação |
| POST | `/arquivos` | Envio de `.md` (multipart) |
| GET | `/arquivos/{id}/conteudo?idUsuario=X` | Conteúdo do arquivo, só para o dono |
| DELETE | `/arquivos/{id}?idUsuario=X` | Exclusão do arquivo, do objeto e dos chunks |

- **Regras que vale citar**: só `.md` no MVP (PDF e TXT voltam `400`); e-mail ou nome de arquivo repetido voltam `409` com mensagem; arquivo de outro usuário volta `404`; as respostas de erro nunca mostram stack trace.
- **Banco**: migrations Flyway V1 a V3, com as tabelas `tb_usuarios`, `tb_arquivos` e `tb_chunks_arquivo` (coluna `vector(1024)`). Um arquivo só pode ficar `PROCESSADO` se tiver provedor, modelo, versão e dimensão do embedding registrados.
- **Armazenamento plugável**: a interface `ArmazenamentoArquivos` tem duas implementações, pasta local e S3, e a escolha vem de uma variável de ambiente. A mesma API funciona na demo e na nuvem.

## Frontend (Victor)

Repositório: `filemind-frontend`. Integração no [PR #1](https://github.com/faculdade-ads-senai/filemind-frontend/pull/1).

- **Stack**: React 19, Vite 7, Tailwind CSS 4.
- **Telas**: Login/Criar conta; Início (lista com status ao vivo, busca, envio, exclusão); Arquivo (Markdown + chat com escopo "Este arquivo" ou "Todos os arquivos", com fontes); Perguntar (chat geral).
- **Integração**: `src/api.js` concentra as chamadas, e o Vite faz proxy de `/api` para o backend e de `/rag` para o RAG. A lista se atualiza sozinha a cada 3 s enquanto há arquivo na fila. A sessão fica no `localStorage`.
- **Do protótipo para o MVP**: o visual foi mantido. Saíram os dados fictícios e os itens sem backend (pastas, configurações). O Markdown passou a ser renderizado sem `dangerouslySetInnerHTML`, o que fecha uma brecha de XSS.

## RAG (Luís)

Repositório: [`filemind-rag`](https://github.com/faculdade-ads-senai/filemind-rag) (Python).

- **Por que RAG**: o modelo não "sabe" o conteúdo dos arquivos do usuário. O RAG recupera os trechos relevantes e entrega ao modelo só esse contexto, o que reduz a invenção e permite mostrar as fontes.
- **Chunking**: trechos de até 2.000 caracteres com 200 de sobreposição. O corte prefere títulos e parágrafos, não quebra bloco de código e guarda o título da seção nos metadados.
- **Embeddings**: `bge-m3` (1.024 dimensões, multilíngue) via Ollama. O provedor, o modelo e a versão ficam gravados com cada arquivo.
- **Busca**: distância de cosseno no pgvector (`<=>`), top 5, filtrada pelo usuário e pelo mesmo modelo e versão de embedding. Um usuário nunca recebe trecho de outro.
- **Similaridade mínima** (`RAG_SIMILARIDADE_MINIMA`, 0,35): o top 5 sempre traz "os menos distantes", mesmo sem relação com a pergunta. Trechos abaixo do limite são descartados. Na medição, as perguntas sobre os arquivos deram 0,41 a 0,62 e as de fora 0,19 a 0,35. Sem esse filtro, o modelo de 3B respondia "a capital da França é Paris" citando um arquivo do usuário.
- **Resposta**: `qwen2.5:3b` com temperatura 0,2 e instrução de usar só o contexto e citar as fontes como [1] e [2]. Se nenhum trecho passa do limite, responde "Nao encontrei informacoes relevantes nos seus arquivos." sem chamar o modelo.
- **Arquitetura neutra**: provedores de embedding e de chat e o armazenamento ficam atrás de interfaces. Trocar o Ollama por um serviço gerenciado, ou a pasta pelo S3, não muda o núcleo.
- **Pronto para nuvem**: `lambda_function.py` já tem os dois handlers, a indexação disparada pelo S3 e a pergunta via HTTP. Na demo, os mesmos módulos rodam no `servidor_local.py`.
- **Testes**: 19 testes unitários, sem banco nem Ollama.

## Roteiro da demo (cerca de 5 min)

1. Login com a conta da demo.
2. Enviar um arquivo de `ambiente-local/exemplos` e mostrar Na fila → Indexando → Pronto.
3. Abrir o arquivo e fazer uma pergunta sobre ele. Mostrar a resposta e as fontes.
4. Trocar para "Todos os arquivos" e fazer uma pergunta que cruza arquivos. Com `Notas de reunião.md` e `Roadmap Q3.md` enviados, "Em que mês do roadmap entra a busca por conteúdo decidida na reunião?" respondeu "agosto" citando os dois arquivos nas duas vezes em que foi testada. Já "O que foi decidido sobre a busca e quando ela entra no roadmap?" acertou só uma de duas vezes, então é melhor evitar.
5. Fazer uma pergunta fora do conteúdo ("Qual a capital da França?") e mostrar que ele não inventa.

Antes da aula: subir tudo, fazer uma pergunta para aquecer o modelo e ter prints ou vídeo como plano B.

## Se um serviço cair (testado em 26/11)

Cada serviço foi derrubado com a stack no ar, um de cada vez.

| Serviço fora | O que acontece | Como volta |
|---|---|---|
| RAG | O envio funciona e o arquivo fica "Na fila". O chat mostra "Não foi possível concluir a operação (HTTP 500)". | Ao religar o RAG, o worker processa a fila sozinho, em cerca de 10 s. |
| Ollama | O arquivo enviado vai para "Erro" e o chat mostra "Erro interno do RAG". O `/saude` do RAG continua "ok", porque não consulta o Ollama. | Religar o Ollama. O arquivo com erro só volta com `POST /indexar/{id}` no RAG (reindexou em 8 s), porque a tela ainda não tem botão. |
| Backend | Login, lista e envio mostram "Não foi possível concluir a operação (HTTP 500)". A lista tem o botão "Atualizar arquivos". O chat continua respondendo, porque o RAG lê o banco direto. | Religar o backend, em cerca de 25 s. |

## Limitações e trabalhos futuros

- **Autenticação por token**: hoje o front envia o `idUsuario`. O próximo passo é o login emitir um token (JWT) e o backend derivar o usuário dele.
- **Nuvem** (entrega de Computação em Nuvem): S3 no lugar da pasta, RAG em AWS Lambda, PostgreSQL gerenciado e monitoramento com Prometheus e Grafana.
- **Desempenho**: na CPU cada resposta levou de 16 a 29 s no teste de 26/11. O "não encontrei" sai em cerca de 5 s, porque não chama o modelo. Com GPU ou provedor gerenciado, cai para poucos segundos.
- **Funcionalidades**: outros formatos (PDF, DOCX), pastas, reindexação pela tela (o RAG já tem `POST /indexar/{id}`) e renderização completa de Markdown (tabelas e código).
