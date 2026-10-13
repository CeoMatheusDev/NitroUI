# Etapa 24.10 — Benchmark headless: workload de widgets

Versão mantida: 0.1.0. Nenhuma API pública da biblioteca foi modificada
(`src/` intocado; somente `bench/headless.zig`).

## Escopo

Segundo workload no bench (`case=widget`) cobrindo o caminho quente real —
eventos, layout vertical, IDs e interação — reutilizando o harness temporal da
24.9 (warm-up 30, 300 frames medidos, min/med/p90/max). O caso `rect`
permanece como referência de geometria pura.

## Implementação (`bench/headless.zig`)

- `Workload = enum { rect, widget }`; `runCase(count, workload)` com despacho
  `comptime` (custo zero em runtime); saída ganha o campo `case={s}` inicial.
- `emitWidgets`: 1 `pointer_move` por frame + região de layout
  (`width=2048`, altura `count*20`, sem espaçamento) + 1 `button()` de ID
  inteiro por linha. Ponteiro fixo em (5,5) paira sobre o primeiro botão de
  forma determinística; todos os botões usam mesma textura/clip e continuam
  em 1 draw command.
- Validações idênticas ao caso rect (slices, cobertura de índices, checksum).

## Resultados (Fedora, Zig 0.17.0, `-Doptimize=ReleaseFast`, 2 execuções)

`ns_widget_med` (run1 / run2), checksums iguais ao rect em todos os tamanhos:

| widgets | rect | widget |
|---|---|---|
| 64 | 12–13 | 29 |
| 256 | 14 | 30 |
| 1024 | 14 | 31 / 30 |
| 4096 | 14 | 31 / 30 |

Constante numa faixa de 64× nos dois casos: O(n) no caminho de geometria e no
caminho completo de widgets. Custo incremental de interação+layout+input por
widget ≈ 16ns (≈2,2× o custo de geometria pura). Geometria e batching
idênticos (mesmos checksums 192300/768300/3072300/12288300): sem regressão.

## Validação executada (Zig 0.17.0)

```sh
zig fmt --check build.zig src bench   # limpo
zig build test --summary all          # 79/79 passed
zig test src/root.zig                 # 79/79 passed
zig build bench -Doptimize=ReleaseFast  # 2×, acima
```

## Limites

- IDs inteiros; custo de hashing de strings e de escopos push/pop por widget
  não está incluído — candidato a terceiro workload.
- Sem pressionamento/clique (só hover); sem checkbox/slider, círculos ou
  rounded rects; sem unicode/teclado.
- Números específicos da máquina; baseline relativa.
