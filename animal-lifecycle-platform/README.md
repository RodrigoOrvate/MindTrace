# Animal Lifecycle Platform

Projeto separado do MindTrace para gestão do ciclo de vida dos animais, com foco em segurança.

## Instalação para quem recebeu a pasta do MindTrace

Se você recebeu a pasta completa do MindTrace e quer habilitar também o aplicativo Animal Lifecycle, siga nesta ordem:

1. Abra terminal em `animal-lifecycle-platform/backend`.
2. Crie e ative o ambiente Python (`.venv`).
3. Instale dependências com `pip install -r requirements.txt`.
4. Crie `backend/.env` com segredos e regras de rede (não subir para GitHub).
5. Crie o primeiro usuário via `python scripts/create_user.py` com `USER_BOOTSTRAP_ENABLED=1`.
6. Inicie o backend com `uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload`.
7. Abra `animal-lifecycle-platform/mobile`, instale dependências (`npm install`) e rode (`npx expo start --web`).
8. No terminal do MindTrace, configure as variáveis `MINDTRACE_SYNC_*` para sincronização.

Resumo rápido:
- `.venv` = ambiente Python local.
- `.env` = segredos/configuração local.
- Não compartilhe `.env`, banco `.db` ou backups em repositório público.

## `.venv` x `.env` (não são a mesma coisa)

- `.venv`: ambiente virtual do Python (pacotes).  
- `.env`: arquivo de configuração/segredos (variáveis de ambiente).

## 1) PC principal (backend)

```powershell
cd "<CAMINHO_DO_PROJETO>\animal-lifecycle-platform\backend"
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

### 1.1 Descobrir IP do PC principal

```powershell
ipconfig
```

Use o valor de `Endereço IPv4` da interface conectada ao Wi-Fi.

### 1.2 Criar `.env` do backend (apenas local)

Crie `animal-lifecycle-platform/backend/.env` com valores de exemplo (substitua):

```env
DATABASE_URL=sqlite:///./animal_lifecycle.db

SYNC_SECRET=<SEGREDO_FORTE_1>
MINDTRACE_ALLOWED_ROOTS=<PASTA_MINDTRACE_DATA_EXPERIMENTOS>
SYNC_MAX_SKEW_SECONDS=120

AUTH_SECRET=<SEGREDO_FORTE_2>
AUTH_TOKEN_TTL_SECONDS=43200
AUTH_ALLOWED_CIDRS=127.0.0.1/32;::1/128;<SUBREDE_WIFI>/24
AUTH_LOGIN_ALLOWED_CIDRS=127.0.0.1/32;::1/128;<IP_PC_PRINCIPAL>/32
AUTH_ADMIN_ALLOWED_CIDRS=127.0.0.1/32;::1/128;<IP_PC_PRINCIPAL>/32
```

## 2) Contas de usuário (com rastreabilidade)

Cada conta possui:
- nome completo
- email
- usuário
- senha
- perfil admin apenas para a primeira conta bootstrap

Criar primeiro usuário (recomendado admin):

```powershell
cd "<CAMINHO_DO_PROJETO>\animal-lifecycle-platform\backend"
.venv\Scripts\Activate.ps1
$env:USER_BOOTSTRAP_ENABLED="1"
python scripts\create_user.py
$env:USER_BOOTSTRAP_ENABLED="0"
```

Importante:
- `create_user.py` fica bloqueado por padrão.
- só executa quando `USER_BOOTSTRAP_ENABLED=1` for definido temporariamente.
- a opção de admin só aparece quando ainda não existe nenhum admin no banco.
- após existir um admin, novas contas criadas pelo script serão sempre usuário comum.

### Gestão de contas via API (somente admin)

- `POST /auth/users` cria conta
- `GET /auth/users` lista contas
- além de admin, o acesso só é liberado se o IP de origem estiver em `AUTH_ADMIN_ALLOWED_CIDRS`
- recomendação: usar apenas `localhost` e o `/32` do computador principal
- `POST /auth/users` não permite criar novo admin (bloqueio de política no servidor)

### Login

- `POST /auth/login`
- `GET /auth/me`

## 3) Auditoria por responsável

As alterações que entram no histórico do animal agora guardam o responsável:
- nome da pessoa
- username
- email

Isso é anexado no `payload` dos eventos (ex.: criação de animal, edição de cadastro, eventos manuais, exclusão de registro, eutanásia).

## 4) Subir backend

```powershell
cd "<CAMINHO_DO_PROJETO>\animal-lifecycle-platform\backend"
.venv\Scripts\Activate.ps1
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

## 5) App web/mobile

Crie `animal-lifecycle-platform/mobile/.env` (local):

```env
EXPO_PUBLIC_API_BASE_URL=http://<IP_PC_PRINCIPAL>:8000
```

Rodar:

```powershell
cd "<CAMINHO_DO_PROJETO>\animal-lifecycle-platform\mobile"
npm install
npx expo start --web
```

## 6) Integração MindTrace

No terminal do MindTrace:

```powershell
$env:MINDTRACE_SYNC_ENABLED="1"
$env:MINDTRACE_SYNC_URL="http://127.0.0.1:8000"
$env:MINDTRACE_SYNC_SECRET="<MESMO_SYNC_SECRET_DO_BACKEND_ENV>"
$env:MINDTRACE_SYNC_ID_CC_DEFAULT="<ID_CC_PADRAO>"
```

## 7) Backup local -> Drive

```powershell
$env:ANIMAL_DB_PATH="<CAMINHO_DO_PROJETO>\animal-lifecycle-platform\backend\animal_lifecycle.db"
$env:ANIMAL_BACKUP_DIR="<PASTA_DO_DRIVE_PARA_BACKUPS>"
$env:ANIMAL_BACKUP_RETENTION_DAYS="30"
powershell -ExecutionPolicy Bypass -File "<CAMINHO_DO_PROJETO>\animal-lifecycle-platform\ops\run_backup.ps1"
```

Agendar backup automático:

```powershell
powershell -ExecutionPolicy Bypass -File "<CAMINHO_DO_PROJETO>\animal-lifecycle-platform\ops\register_backup_task.ps1"
```

## 8) Segurança de rede

Para múltiplos celulares, o correto é restringir por **sub-rede**, não por “mesmo IP”.

Use `AUTH_ALLOWED_CIDRS` para permitir apenas localhost + sub-rede autorizada.
Use `AUTH_LOGIN_ALLOWED_CIDRS` para definir de onde o login pode ser aceito.
Use `AUTH_ADMIN_ALLOWED_CIDRS` para restringir funções administrativas ao computador principal.

Obs.: quando login vem de IP não autorizado, a API responde `401 Login invalido` (mensagem genérica), sem revelar se usuário/senha estavam corretos.

## 9) Git hygiene

O `.gitignore` foi reforçado para não subir:
- `.env` e variações locais
- `.venv`, `node_modules`, `__pycache__`, caches
- bancos locais (`*.db`, `*.sqlite`)
- pastas temporárias de backup/teste

## Testes de segurança

```powershell
cd "<CAMINHO_DO_PROJETO>\animal-lifecycle-platform\backend"
.venv\Scripts\Activate.ps1
pytest -q tests\test_auth_security.py tests\test_sync_security.py -p no:cacheprovider
```



