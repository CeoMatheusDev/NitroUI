# Etapa 24.17 — Sincronização da documentação (81 testes, MissingStorage)

Versão mantida: 0.1.0. Nenhum código alterado; somente `README.md`.

## Mudanças

- Contagens 80/80 → 81/81.
- Contrato `MissingStorage` documentado na seção de ownership (retornado por
  `widgetState`/`reserve*` sem armazenamento anexado, distinto de
  `OutOfCapacity`).

## Revalidação (Zig 0.17.0, sem mudanças de código)

```sh
zig fmt --check build.zig src bench   # limpo
zig build test --summary all          # 81/81 (cache, conteúdo idêntico)
zig test src/root.zig                 # 81/81
zig build bench -Doptimize=ReleaseFast  # 12 linhas case=*, ok
```
