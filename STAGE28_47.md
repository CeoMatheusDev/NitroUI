# NitroUI — Etapa 28.47: incluir o manifesto no controle de formatação

## Problema
O validador compartilhado entre CI e execução local verificava `build.zig`, `src`, `bench` e `examples`, mas omitia `build.zig.zon`, manifesto essencial à distribuição Zig.

## Alteração
- `tools/validate_zig_017.sh`: `zig fmt --check build.zig build.zig.zon src bench examples`.
- `tools/test_validate_zig_017.sh`: atualizada a expectativa exata do comando de formatação no autoteste com compilador simulado, incluindo a propagação de falhas e a ordem dos comandos.
- Nenhuma alteração no runtime, API, alocações ou versão (`0.2.0`).

## Validação
- Sintaxe Shell e autoteste offline executados.
- Verificação de integridade do arquivo ZIP.
- Zig 0.17.0 não disponível: formatação Zig, compilação, testes Zig, integração e benchmarks **não executados**.

## Risco residual
O comportamento de `zig fmt --check` sobre `build.zig.zon` precisa ser confirmado com o compilador Zig 0.17.0 real. Os testes com Zig simulado validam somente o comando solicitado e o fluxo de erro.
