# Etapa 28.43 — CI verifica o próprio validador

## Objetivo
Evitar que regressões nos scripts de validação passem despercebidas no pipeline de CI.

## Alteração
O workflow `.github/workflows/ci.yml` agora executa `sh -n` nos dois scripts, roda o autoteste offline do validador e confirma a versão exata `0.17.0` do compilador antes das tarefas Zig existentes. Os passos anteriores de formatação, testes Debug/ReleaseFast, integração Debug/ReleaseFast e benchmark permanecem.

## Contratos
O autoteste utiliza Zig simulado exclusivamente para verificar a infraestrutura; as etapas seguintes do CI continuam configuradas para usar Zig real. Não há alterações no runtime, nas APIs públicas, na versão do pacote ou em dependências Zig.

## Validação local
Executar `sh -n tools/validate_zig_017.sh`, `sh -n tools/test_validate_zig_017.sh` e `sh tools/test_validate_zig_017.sh`. A execução do workflow GitHub Actions e a compilação Zig 0.17.0 não são comprovadas por estes comandos.
