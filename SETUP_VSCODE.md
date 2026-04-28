# Setup VSCode (Primeira Vez)

Guia para compilar o MindTrace no VSCode sem paradoxo de dependencias.

## O problema antigo (e a solucao)

Antes, o CMake no VSCode falhava porque `onnxruntime_sdk/` ainda nao existia.
Esse SDK era baixado por script separado, o que confundia o fluxo inicial.

Agora o bootstrap e unico:
- `qt\scripts\build.bat --deps-only` cria/verifica `onnxruntime_sdk/`
- Depois disso, o CMake do VSCode funciona normalmente

## Pre-requisitos (instalar uma vez)

1. Visual Studio 2022+ com workload `Desktop development with C++`
2. Qt 6.11.0 em `C:\Qt\6.11.0\msvc2022_64`
3. CMake 3.25+ no PATH
4. VSCode com extensoes:
- `C/C++` (Microsoft)
- `CMake Tools` (Microsoft)

## Primeira execucao (passo a passo)

1. Abra PowerShell na raiz do repo:
```powershell
cd C:\MindTrace
```

2. Rode bootstrap de dependencias ONNX (uma vez):
```powershell
qt\scripts\build.bat --deps-only --gpu DML
```

Use `--gpu CUDA` se sua maquina for NVIDIA.

3. Abra o projeto no VSCode:
```powershell
code .
```

4. No VSCode:
- `Ctrl+Shift+P` -> `CMake: Select a Kit`
- Selecione `Visual Studio 17 2022 x64` (ou superior)
- `CMake: Select Configure Preset` -> `Release` (se aparecer)
- `CMake: Configure`
- `CMake: Build`

5. Execute o app:
- Pelo VSCode (Run/Debug), ou
- Diretamente: `qt\build\Release\MindTrace.exe`

## Fluxo diario (depois da primeira vez)

- Build incremental no VSCode: `CMake: Build`
- Ou terminal:
```powershell
cmake --build qt\build --config Release --parallel
```

## Script oficial (resumo)

Scripts ativos em `qt\scripts\`:
- `build.bat`: bootstrap + build completo (ou `--deps-only`)
- `run.bat`: abre o exe ja compilado
- `build_installer.bat`: gera instalador (release)
- `setup_onnx.ps1`: backend interno chamado pelo `build.bat`

## Troubleshooting rapido

- Qt nao encontrado:
  - Ajuste `QT_DIR` em `qt\scripts\build.bat`
- ONNX SDK ausente:
  - Rode novamente `qt\scripts\build.bat --deps-only --gpu DML`
- CMake travado em cache antigo:
  - `CMake: Delete Cache and Reconfigure`
- DLL faltando ao abrir o exe:
  - Rode `qt\scripts\build.bat` uma vez (sem `--deps-only`)

