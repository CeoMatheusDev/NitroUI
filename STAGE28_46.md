# NitroUI — Etapa 28.46

## Escopo

Fortalecer o autoteste do validador local/CI sem modificar o runtime Zig.

## Falha de cobertura identificada

O autoteste afirmava que `tools/validate_zig_017.sh` executava os comandos na raiz do projeto mesmo quando chamado de outro diretório, mas verificava apenas a ordem dos comandos. Uma regressão que removesse o `cd` poderia passar inadvertidamente.

## Mudança

- `tools/test_validate_zig_017.sh`: o Zig simulado registra o diretório de trabalho de cada comando de validação.
- No cenário de sucesso, o autoteste exige exatamente seis registros e compara cada um com a raiz do projeto.
- Não há mudanças em APIs públicas, build.zig, runtime ou dependências.

## Validação executada

- `sh -n tools/test_validate_zig_017.sh`: passou.
- `sh -n tools/validate_zig_017.sh`: passou.
- `sh tools/test_validate_zig_017.sh`: passou, incluindo as seis verificações de diretório de trabalho.
- ZIP verificado por CRC após criação.

Zig 0.17.0 não está disponível neste ambiente. Não foram executados testes Zig, compilação, integração real ou benchmarks. Versão permanece 0.2.0.
