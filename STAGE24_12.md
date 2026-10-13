# Etapa 24.12 — Benchmark headless: workload de IDs hierárquicos

Versão mantida: 0.1.0. Nenhuma API pública da biblioteca foi modificada
(`src/` intocado; somente `bench/headless.zig`).

## Escopo

Terceiro workload (`case=idstr`) cobrindo o hot path de IDs: mesmo caminho de
`widget` (eventos, layout, botões), mas cada botão usa ID hierárquico com
escopo string externo + escopo inteiro por linha. O delta `widget → idstr`
quantifica hashing FNV-1a + push/pop de escopos por widget.

## Implementação (`bench/headless.zig`)

- `Workload = enum { rect, widget, idstr }`; despacho `comptime`, harness e
  validações inalterados.
- `emitIdWidgets`: `pushId("list")`, por linha `pushIdInteger(i)` +
  `widgetId("btn")` + `button` + `popId()`, `popId()` final. IDs distintos e
  determinísticos; geometria e batching idênticos aos demais casos.

## Resultados (Fedora, Zig 0.17.0, `-Doptimize=ReleaseFast`, 2 execuções)

`ns_widget_med` (run1 / run2); checksums iguais em todos os casos e tamanhos:

| widgets | rect | widget | idstr |
|---|---|---|---|
| 64 | 13 / 12 | 29 / 28 | 33 / 32 |
| 256 | 13 | 28 | 31 |
| 1024 | 13 | 30 | 32 |
| 4096 | 13–14 | 30 | 32 |

`idstr` constante em 31–33ns numa faixa de 64×: O(n) também no caminho de
IDs. Custo de hashing hierárquico + scopes ≈ 2–3ns/widget sobre o caminho de
IDs inteiros. Sem regressão funcional ou de batching (1 comando em todos).

## Validação executada (Zig 0.17.0)

```sh
zig fmt --check build.zig src bench   # limpo
zig build test --summary all          # 79/79 passed
zig build bench -Doptimize=ReleaseFast  # 2×, acima (12 linhas case=*)
```

## Limites

- Labels fixos curtos ("list"/"btn"); custo de labels longas/variadas e de
  profundidades maiores de escopo não medido.
- Sem clicks, teclado/unicode, checkbox/slider ou primitivas não-retangulares
  na temporização. Números específicos da máquina.
