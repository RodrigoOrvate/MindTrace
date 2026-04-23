# Animal Lifecycle Platform

Aplicativo para gestao do ciclo de vida de animais, com autenticacao, auditoria e sincronizacao com o MindTrace.

## Arquitetura

- `backend/`: FastAPI + SQLAlchemy (PostgreSQL ou SQLite)
- `mobile/`: Expo (web/mobile)
- `qt/` (MindTrace, fora desta pasta): cria experimentos e sincroniza sessoes

Regra atual:
- Experimentos sao criados no MindTrace.
- O app nao possui fluxo de criacao manual de experimento.
- O campo `responsavel` e escolhido no MindTrace a partir dos usuarios pesquisadores (nao-admin) cadastrados no backend.

## 1) Preparacao no PC principal

### 1.1 Backend (venv)

```powershell
cd "<CAMINHO_DO_PROJETO>\animal-lifecycle-platform\backend"
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Observacao:
- `.venv` e o ambiente virtual Python.
- `.env` e o arquivo de variaveis de ambiente. Sao coisas diferentes.

### 1.2 Descobrir IP do PC principal

Use um destes comandos e anote o IPv4 da interface em uso:

```powershell
ipconfig
# ou
Get-NetIPAddress -AddressFamily IPv4
```

### 1.3 Criar `backend/.env`

Crie `animal-lifecycle-platform/backend/.env` com valores reais do seu ambiente (somente exemplo abaixo):

```env
DATABASE_URL=postgresql://<USER>:<PASSWORD>@localhost:5432/<DB_NAME>

AUTH_SECRET=<GERAR_TOKEN_FORTE>
AUTH_TOKEN_TTL_SECONDS=43200

SYNC_SECRET=<GERAR_TOKEN_FORTE_DIFERENTE>
SYNC_MAX_SKEW_SECONDS=120
# Opcional (modo restrito por raiz):
# MINDTRACE_ALLOWED_ROOTS=<PASTA_BASE_DOS_EXPERIMENTOS_MINDTRACE>
# Opcional: permitir sync de qualquer pasta absoluta escolhida no MindTrace
# (use 1 somente quando voces realmente usam diretorios livres por pesquisador)
MINDTRACE_ALLOW_ANY_PATH=1

AUTH_ALLOWED_CIDRS=127.0.0.1/32;::1/128;<SUA_REDE_LOCAL>
AUTH_LOGIN_ALLOWED_CIDRS=127.0.0.1/32;::1/128;<SUA_REDE_LOCAL>
AUTH_ADMIN_ALLOWED_CIDRS=127.0.0.1/32;::1/128;<IP_PC_PRINCIPAL>/32
AUTH_ADMIN_ALLOWED_MACS=<MAC_DO_PC_PRINCIPAL>

CORS_ALLOWED_ORIGINS=http://localhost:8081;http://localhost:19006;http://<IP_PC_PRINCIPAL>:8081
```

Gerar segredo forte (rode 2x):

```powershell
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

## 2) Criar usuario admin inicial

Somente no PC principal:

```powershell
cd "<CAMINHO_DO_PROJETO>\animal-lifecycle-platform\backend"
.venv\Scripts\Activate.ps1
$env:USER_BOOTSTRAP_ENABLED="1"
python scripts\create_user.py
$env:USER_BOOTSTRAP_ENABLED="0"
```

Politica:
- Depois que ja existe admin, nao e permitido criar novo admin via app.
- Contas comuns (pesquisadores) sao criadas pelo admin autenticado no PC principal.

## 3) Rodar backend

```powershell
cd "<CAMINHO_DO_PROJETO>\animal-lifecycle-platform\backend"
.venv\Scripts\Activate.ps1
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

## 4) Rodar app (web ou celular)

```powershell
cd "<CAMINHO_DO_PROJETO>\animal-lifecycle-platform\mobile"
npm install
npx expo start
```

Web:
- `npm run web` ou tecla `w` no Expo.

Celular:
- Mesmo Wi-Fi do PC principal.
- Em `mobile/.env`, configure:

```env
EXPO_PUBLIC_API_BASE_URL=http://<IP_PC_PRINCIPAL>:8000
```

## 5) Integracao com MindTrace (qt)

Antes de iniciar o MindTrace no PC principal, configure no terminal/sessao:

```powershell
$env:MINDTRACE_SYNC_ENABLED="1"
$env:MINDTRACE_SYNC_URL="http://127.0.0.1:8000"
$env:MINDTRACE_SYNC_SECRET="<MESMO_SYNC_SECRET_DO_BACKEND>"
```

Comportamento:
- No setup de criacao de experimento (NOR/CA/CC/EI), o MindTrace consulta pesquisadores ativos (nao-admin) via endpoint seguro de sync local.
- O responsavel selecionado e salvo no `metadata.json` do experimento.
- Ao salvar sessoes, a sincronizacao gera eventos no Animal Lifecycle e inclui `responsible_username` no payload historico.
- Se o experimento puder ser salvo em qualquer pasta (Desktop, pasta pessoal etc.), habilite `MINDTRACE_ALLOW_ANY_PATH=1` no backend.
- Com `MINDTRACE_ALLOW_ANY_PATH=1`, `MINDTRACE_ALLOWED_ROOTS` pode ser omitido.

## 6) Seguranca aplicada

- Segredos em `.env` (nao no codigo).
- Endpoints de sync aceitam apenas loopback local + assinatura HMAC (`SYNC_SECRET`).
- Login admin restrito a IP/MAC permitidos.
- Mensagem de erro de login padronizada (nao revela se usuario existe).
- Fluxo de criacao de usuarios administrativos bloqueado no app.

## 7) Git e arquivos sensiveis

Ja ignorados no `.gitignore`:
- `.env`, `.env.*` (exceto exemplos)
- `.venv/`
- bancos locais e dumps
- `mobile/node_modules/`, `mobile/.expo/`
- chaves/certificados

Antes de commit/push:

```powershell
git status
git diff -- . ':!*.md'
```

Revise sempre para garantir que nenhum segredo foi incluido.

## 8) Configuracoes no aplicativo (Engrenagem)

Foi adicionada uma tela de configuracoes acessivel pelo icone `⚙` no topo.

Permissoes por perfil:
- Usuario comum: altera apenas as proprias preferencias (`tema` e `idioma`).
- Admin local: alem disso, pode alterar o formato global de data para todos.

Opcoes atuais:
- Tema: `light` ou `dark`
- Idioma: `pt`, `en`, `es`
- Formato global de data (admin):
  - `DD/MM/YYYY`
  - `MM/DD/YYYY`
  - `YYYY-MM-DD`

## 9) Busca por data na lista de animais

A busca principal agora aceita:
- ID interno (ex.: `22042026-A101`)
- Data de entrada em `YYYY-MM-DD`
- Data de entrada em `DD/MM/YYYY`

Exemplos:
- `2026-04-22`
- `22/04/2026`

## 10) Observacoes de seguranca (sem vazamento)

- Nunca colocar tokens, segredos, IP real, usuario real ou senha real em README.
- Usar somente placeholders em exemplos (`<IP_PC_PRINCIPAL>`, `<SYNC_SECRET>`, etc.).
- Toda configuracao sensivel continua fora do codigo, em `.env` local.