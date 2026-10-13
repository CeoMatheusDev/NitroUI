# Etapa 24.15 — Sincronização da documentação e revalidação

Versão mantida: 0.1.0. Nenhum código alterado (`src/` e `bench/` intactos);
somente `README.md` atualizado para refletir as etapas 24.12–24.14.

## Mudanças no README

- Contagens: 79/79 → 80/80 (Debug e ReleaseFast).
- Bench: três workloads (`rect`, `widget`, `idstr`) com medianas de referência
  ~14 / ~30 / ~32ns por widget; nota sobre o teste de estado estacionário.
- Limitações: item "string-ID hashing não medido" removido (medido na 24.12
  para labels curtos; ressalva de labels longas/variadas mantida); item de
  alocações atualizado para estrutural + operacional, com a ressalva de
  contador de heap.

## Revalidação (Zig 0.17.0, sem mudanças de código desde a última passagem)

```sh
zig build-exe do exemplo do README  # compila e roda: 16v/24i/1c por frame
zig fmt --check build.zig src bench  # limpo
zig build test --summary all         # 80/80 (cache de conteúdo idêntico)
zig build test -Doptimize=ReleaseFast --summary all  # 80/80 (idem)
zig test src/root.zig                # 80/80
zig build bench -Doptimize=ReleaseFast  # 12 linhas case=*, ok
```

Resultados de cache são válidos aqui porque são endereçados por conteúdo e
nenhum arquivo coberto mudou desde as execuções completas das etapas
anteriores. Nada a corrigir; nenhuma regressão.
