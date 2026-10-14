# Etapa 28.41 — Distribuição dos scripts de validação

## Problema

O `build.zig.zon` tinha uma lista explícita de caminhos de pacote (`.paths`) que excluía `tools/`. Assim, uma distribuição criada pelo mecanismo de empacotamento Zig não incluiria os scripts de validação das etapas 28.38–28.40.

## Alterações

- `build.zig.zon`: adiciona `"tools"` à lista `.paths`, preservando nome, versão e dependências.
- `tools/test_validate_zig_017.sh`: verifica a presença de `tools` no manifesto e dos dois scripts no projeto.

## Validação

Executar `sh -n tools/*.sh` e `sh tools/test_validate_zig_017.sh`. A execução desses testes usa um Zig simulado e **não** demonstra compilação Zig 0.17.0. O compilador continua indisponível. A inclusão de `tools` na distribuição foi verificada estaticamente, não via `zig build --release=...` ou `zig fetch`.

## Limites

Sem mudanças de runtime, API pública, alocação, backend ou versão (`0.2.0`).
