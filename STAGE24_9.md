# Etapa 24.9 — Benchmark headless: latência reproduzível por frame

Versão mantida: 0.1.0. Nenhuma API pública da biblioteca foi modificada
(`src/` intocado; somente `bench/headless.zig`).

## Escopo

Instrumentação temporal do workload determinístico existente, separando
warm-up, execução medida e consolidação, sem acoplar relógio ao módulo
NitroUI. Workload inalterado (retângulos sólidos com batching em 1 comando);
a mudança isola o harness para que deltas futuros de workload sejam
comparáveis contra esta baseline.

## Implementação (`bench/headless.zig`)

- `warmup_frames = 30` excluídos da medição; `frames_per_case = 300` medidos.
- Janela temporizada por frame: de antes de `beginFrame()` até depois de
  `releaseFrame()` (custo CPU completo pago pela engine por frame).
- `monoNanos()`: relógio monotônico só no harness, com o mapeamento de IDs da
  std do Zig 0.17.0 (`CLOCK_MONOTONIC` no Linux, `UPTIME_RAW` no Darwin,
  performance counter no Windows, `MONOTONIC` no WASI). Falha de relógio
  retorna `error.ClockUnavailable` (falha ruidosa, sem zeros silenciosos).
  Validado apenas no Linux; demais ramos seguem padrões da std, não testados.
- Estatísticas sem alocação: array fixo `[300]u64` na stack + insertion sort;
  saída `ns_frame_min/med/p90/max` e `ns_widget_med`.
- Checagens determinísticas preservadas (slices, cobertura de índices,
  checksum, capacidade em bytes).

## Resultados (Fedora, Zig 0.17.0, `-Doptimize=ReleaseFast`, 2 execuções)

| widgets | ns_frame_med (run1/run2) | ns_widget_med | checksum |
|---|---|---|---|
| 64 | 878 / 877 | 13 | 192300 |
| 256 | 3685 / 3663 | 14 | 768300 |
| 1024 | 14566 / 14558 | 14 | 3072300 |
| 4096 | 58715 / 58847 | 14 | 12288300 |

Medianas estáveis entre execuções; min/med/p90 próximos (baixo ruído, max com
outliers esporádicos como esperado). `ns_widget_med` constante em 13–14ns numa
faixa de 64× confirma escalabilidade O(n) do caminho de geometria. Checksums
idênticos aos das etapas 24.5–24.8: sem regressão funcional.

## Validação executada (Zig 0.17.0)

```sh
zig fmt --check build.zig src bench   # limpo
zig build test --summary all          # 79/79 passed
zig test src/root.zig                 # 79/79 passed
zig build bench -Doptimize=ReleaseFast  # 2×, acima
```

## Limites (não afirmar além disto)

- Mede só o caminho `drawRect` + frame; widgets reais (IDs, layout, eventos,
  interação) e primitivas diversas (círculos, rounded rects) continuam sem
  temporização — próximo workload candidato.
- Números são específicos da máquina; servem como baseline relativa, não como
  especificação de desempenho.
- Ausência de alocações segue estrutural (nenhuma API quente recebe
  `Allocator`; bench usa só buffers fixos), não demonstrada por contador.
