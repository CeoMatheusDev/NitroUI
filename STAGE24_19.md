# Etapa 24.19 — Teste diferencial semeado da tabela de estados

Versão mantida: 0.1.0. Nenhuma API alterada; 1 teste adicionado em
`src/state.zig` (total 82). Nenhum bug encontrado — cobertura real adicionada
sobre colisões, remoção e reutilização.

## Teste (`seeded operations match linear reference model`)

500 operações mistas (`getOrPut`/`get`/`prune`) com PRNG semeado
(`std.Random.DefaultPrng`, seed `0xC0FFEE`, APIs conferidas na std do 0.17.0)
contra um modelo de referência linear, com espaço de 24 IDs sobre capacidade
16 para forçar colisões, despejos e falhas de tabela cheia deterministicamente.
Cada passo afirma `count` sincronizado; varredura final compara todos os IDs
(valor + `last_seen` + presença). Determinístico: mesma seed, mesma sequência,
em qualquer modo de build.

## Validação executada (Zig 0.17.0)

```sh
zig fmt --check build.zig src bench            # limpo
zig build test --summary all                   # 82/82 (Debug)
zig build test -Doptimize=ReleaseFast --summary all  # 82/82
zig test src/root.zig                          # 82/82
zig build bench -Doptimize=ReleaseFast         # 12 linhas case=*, ok
```

README sincronizado para 82/82.
