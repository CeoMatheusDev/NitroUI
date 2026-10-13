# Etapa 24.7 — Benchmark headless: métricas determinísticas

Versão do pacote: 0.1.0. Nenhuma API pública foi modificada.

## Escopo

- O benchmark agora consome `drawDataView()` (interface recomendada para a engine).
- Verifica os comprimentos dos três slices e a cobertura de índices pelo único draw command.
- Reporta a capacidade estática de armazenamento da geometria em bytes, incluindo um comando, e o custo de geometria por widget.
- Mantém os quatro cenários, 300 frames por cenário, o checksum e os contadores anteriores.
- Não usa heap nem allocator no workload; isso **não prova** ausência de alocações em todos os caminhos da biblioteca.

## Executar no Fedora (Zig 0.17.0)

```sh
zig fmt build.zig src bench
zig fmt --check build.zig src bench
zig build test --summary all
zig test src/root.zig
zig build bench -Doptimize=ReleaseFast
```

## Medir tempo externamente

O benchmark deliberadamente não acopla a biblioteca a uma API de relógio do sistema operacional. Para uma medição inicial do processo completo:

```sh
zig build -Doptimize=ReleaseFast
/usr/bin/time -f 'elapsed=%e user=%U maxrss_kb=%M' ./zig-out/bin/bench_headless
```

Esse tempo inclui inicialização do processo, quatro cenários e impressão dos resultados; **não** representa tempo por frame. Para medir latência por frame de forma reproduzível, será necessário um harness com relógio monotônico na camada de benchmark, warm-up, repetições e estatísticas (mediana/percentis), sem introduzir dependências no módulo NitroUI.

## Limitações

- Somente retângulos sólidos com textura/clip iguais; não mede widgets reais, layout ou processamento de eventos.
- Capacidade em bytes não é RSS e não inclui `Context` nem estruturas externas.
- O teste de `index_count` verifica um único comando e não valida todos os índices individualmente.
- Não foram executados compilação, testes ou benchmarks neste ambiente; validar no Fedora.
