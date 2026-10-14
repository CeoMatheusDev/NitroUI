# Etapa 28.74 — Exemplo de integração e ciclo completo

## 1. Análise

`examples/engine_host.zig` cobria só button/checkbox/slider com hover,
sem texto, foco, resize ou erros. Faltava a prova de que um consumidor
externo consegue operar o ciclo completo só com a API pública.

## 2. Arquivos

| Arquivo | Alteração |
|---|---|
| `examples/full_cycle.zig` | Novo (7 frames, 2 contextos) |
| `build.zig` | `integration` executa `engine_host` + `full_cycle` |
| `STAGE28_74.md` | Este relatório |
| Demais | Preservados |

Versão 0.2.0. Sem dependências, sem mudança de API de biblioteca.

## 3. Implementação

`full_cycle` usa só a API pública (`ui.Context`, `ui.font`,
`ui.text_edit`, `ui.input_events`, `ui.layout`, `ui.draw`):

- Frame 0: fonte validada (`validate()`), `label("Hi")` com largura
  verificada (12 = 7+5), button/checkbox/slider; validação estrutural
  do draw data (cobertura contígua, índices < vértices).
- Frame 1: down+up no mesmo batch → `button` retorna true (clique).
- Frame 2: `requestFocus` + Tab → `focusedId()` avança ao checkbox
  (ordens de submissão idênticas entre frames, via `setNavigationStorage`).
- Frame 3: campo focado consome 2 eventos `text` → editor `"Hi"`.
- Frame 4: resize 800×600 → 1280×720; `drawDataView()` antes de
  `endFrame()` retorna `InvalidFrameState` (contrato).
- Frame 5: contexto minúsculo ([4]v/[6]i/[1]c): `label` retorna
  `OutOfCapacity` com contadores intactos (0/0); o frame ainda fecha
  (`popLayout`/`endFrame`/`releaseFrame`) — rollback funciona.
- Frame 6: contexto principal não afetado; reuso pós-`releaseFrame`
  (`state == .idle`).

Renderer do exemplo valida contenção de clips (não igualdade: o campo
de texto emite sub-clip de conteúdo legítimo) e texturas {0, 7}.
Três bugs do próprio exemplo foram encontrados e corrigidos durante o
desenvolvimento (`widgetId` fora de frame, igualdade de clip,
`label` sem layout) — todos erros do exemplo, nenhum da biblioteca.

## 4. Memória e performance

Só armazenamento do chamador (pilha do `main`); zero alocação.
Complexidade por frame inalterada. Sem benchmark novo (bench existente
passa).

## 5. Validação (Zig 0.17.0 real, cache limpo)

`fmt --check` PASS; `test` Debug/ReleaseFast 208/208; `integration`
Debug/ReleaseFast PASS (ambos os executáveis); `bench` PASS;
`validate_zig_017.sh` exit 0.

## 6. Riscos e próxima etapa

Exemplo ainda headless — sem GPU real (§19 do prompt mestre).
Próxima: 28.75 (validação de draw data, buffers e clipping).
