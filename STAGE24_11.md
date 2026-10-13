# Etapa 24.11 — Documentação de integração (README)

Versão mantida: 0.1.0. Nenhum código da biblioteca foi modificado
(`src/` e `bench/` intactos; criado `README.md`).

## Escopo

Cobrir o critério "Documentação" da 0.2.0: instruções de integração como
módulo local, contratos públicos, ownership/validade, ciclo de frame, exemplo
de uso, comandos de build/teste/bench e limitações honestas.

## Conteúdo do README

- Identidade, versão e requisitos (Zig 0.17.0, single-threaded, sem estado
  global, sem dependências externas obrigatórias).
- Tabela de responsabilidades engine × NitroUI.
- Integração via path dependency (`build.zig.zon` + `addImport`), com o nome
  de módulo `nitro_ui` conferido em `build.zig`.
- Ciclo de frame completo com exemplo (2 frames: eventos, layout, button,
  checkbox, sliderFloat, `drawDataView`, `releaseFrame`).
- Tabela de ownership/validade dos slices + notas de `const`, batching,
  rollback e `endFrame` transacional.
- Comandos oficiais de validação e baselines do bench rotuladas como
  específicas da máquina.
- Limitações da 0.1.0 e pendências (sem promessa de 0.2.0).

## Verificação do exemplo

O exemplo do README foi compilado e executado fora do repo
(`/tmp/opencode/nitro_example.zig`, via `zig build-exe` com o módulo local):

```text
verts=16 idx=24 cmds=1 checked=false volume=0.5
verts=16 idx=24 cmds=1 checked=false volume=0.5
```

16 vértices = button (4) + checkbox desmarcado (4) + slider com fill (8),
1 draw command por batching de mesma textura/clip — consistente com os
contratos documentados.

## Validação executada (Zig 0.17.0)

```sh
zig fmt --check build.zig src bench   # limpo
zig build test --summary all          # 79/79 passed
zig build bench -Doptimize=ReleaseFast  # 8 linhas case=*, ok
```
