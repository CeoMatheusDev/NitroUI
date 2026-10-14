# NitroUI — Etapa 28.38: validação reproduzível

## Escopo

Adicionado `tools/validate_zig_017.sh` para executar a sequência de validação acumulada em um ambiente que tenha exatamente Zig 0.17.0 instalado. Não altera o runtime, o build, os contratos públicos nem a versão (0.2.0).

## Contrato

- Não baixa nem instala compiladores.
- Interrompe com código 127 se `zig` não estiver no `PATH`.
- Interrompe com código 2 se `zig version` não for exatamente `0.17.0`.
- Executa em ordem: `zig build test -Doptimize=Debug`, `zig build test -Doptimize=ReleaseFast`, `zig build integration -Doptimize=Debug`, `zig build bench -Doptimize=ReleaseFast`.
- Usa `set -eu`: qualquer falha interrompe o restante; não mascara resultados.
- Deve ser executado a partir de qualquer diretório: resolve a raiz do projeto pelo caminho do script.

## Uso

```sh
sh tools/validate_zig_017.sh
```

## Validação desta etapa

O script foi executado em ambiente sem `zig`, confirmando a interrupção com status 127. Não foram executados compilação, testes, integração nem benchmarks. Não há afirmação de compatibilidade com Zig 0.17.0 sem execução real.
