# Etapa 24.18 — Pacote de entrega consolidado

Versão mantida: 0.1.0. Nenhum código alterado nesta etapa.

## Pacote

`nitro_ui_milestone24_18.zip` (ao lado do projeto, não dentro dele) contém:

- `build.zig`, `build.zig.zon`
- `src/` (9 módulos)
- `bench/headless.zig`
- `README.md`
- `STAGE*.md` (histórico completo 24.1–24.18)

Excluídos: `.zig-cache/`, artefatos de build e arquivos temporários.

## Verificação do pacote (extração limpa em /tmp)

Extraído para diretório temporário e validado de forma independente:

```sh
zig fmt --check build.zig src bench   # limpo
zig build test --summary all          # 81/81 (Debug)
zig build bench -Doptimize=ReleaseFast  # 12 linhas case=*, checksums ok
```

A cópia extraída compila e passa sem o workspace original, provando que o
pacote é autocontido. Resultado obtido: fmt limpo, 81/81 em
`zig build test`, 12 linhas `case=*` no bench com os checksums
192300/768300/3072300/12288300. Não publicado no GitHub; sem tags ou releases.
