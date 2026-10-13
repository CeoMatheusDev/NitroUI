# Etapa 24.14 — Estado estacionário pós-warm-up

Versão mantida: 0.1.0. Nenhuma API alterada; 1 teste de integração adicionado
(`src/root.zig`, total 80).

## Escopo

Demonstração operacional da meta "zero alocações dinâmicas após warm-up":
como nenhuma API recebe `Allocator` (verificado por inspeção na 24.13), o
significado experimental é reuse total dos buffers fixos. O novo teste roda
40 frames de workload misto e prova estabilidade de todas as capacidades.

## Teste (`stage24_14 post-warm-up frames reuse buffers without growth`)

Workload por frame: 1 evento de ponteiro, `reserveScratch`/`reserveRender` de
16 bytes, região de layout com `button` + `checkbox` + `sliderFloat` (IDs via
`widgetId`) e `widgetState`. Reservas persistentes (32 bytes) e inserção de
estado ocorrem só no frame 0 (warm-up).

A partir do frame 3, todo frame afirma sem falha:
- `scratch`/`render.high_watermark` constantes; `used == 16` (só o transiente
  do frame; o reset ocorre no próximo `beginFrame`);
- `persistent.high_watermark == 32` (sem novas reservas);
- `states.count` constante (mesmos IDs → hits, sem crescimento);
- checksum acumulado exato: 40 × (16v + 24i + 1c) — button 4/6, checkbox
  desmarcado 4/6, slider em 0.5 com fill 8/12, 1 comando por batching.

Ao final: `checked == false`, `scalar == 0.5` (sem clicks fantasmas),
byte persistente `0xAB` intacto e valor de estado `1234` preservado.

## Validação executada (Zig 0.17.0)

```sh
zig fmt --check build.zig src bench            # limpo
zig build test --summary all                   # 80/80 (Debug)
zig build test -Doptimize=ReleaseFast --summary all  # 80/80
zig test src/root.zig                          # 80/80
zig build bench -Doptimize=ReleaseFast         # 12 linhas case=*, ok
```

## Limites e honestidade

O teste prova reuse estável dos buffers proprietários da engine, não a
ausência de `malloc` oculto — esta segue por construção (Zig não aloca heap
sem allocator, e nenhum existe nas assinaturas). A linha correspondente da
matriz 0.2.0 passa a "demonstrado operacionalmente" com essa ressalva
explícita. Resta, antes da 0.2.0: integração contra engine real e as
autorizações de versão/publicação.
