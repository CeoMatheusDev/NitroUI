# Etapa 28.71 — Destravamento da compilação Zig 0.17.0

## Escopo

Corrigir os 12 erros de compilação que bloqueavam `zig build test`,
sem mudar comportamento, APIs públicas ou contratos de memória.
Versão permanece 0.2.0.

## Alterações

- `src/text.zig`: `const glyph` → `const resolved_glyph` em
  `measure()`, `caretOffsetAtX()`, `emitBaseline()` (conflito com
  `fn glyph()` helper de testes). Usos atualizados.
- `src/root.zig`: parâmetro `label` → `widget_label` em `widgetId()`
  e `pushId()` (sombreava método `label`). Assinaturas posicionais
  inalteradas.
- `src/root.zig`: 5× `const clip` → `const clip_rect` em testes +
  6 usos `, clip,` → `, clip_rect,` (sombreavam `pub const clip`).
- `src/root.zig`: `TextRenderFailurePolicy` → `Context.TextRenderFailurePolicy`
  (enum declarado em `Context`).
- `src/root.zig`: `checkpointWidget()` passou de `Error!` para
  `(Error || draw.Error)!` — já retornava `error.OutOfCapacity`,
  ausente do conjunto `Error`. Alinha com `draw.Buffer` e chamadores
  `button`/`slider` que já incluem `draw.Error`.
- `src/text_edit.zig`: 13 ocorrências de `[_]u8{..} ** N` →
  `var storage: [N]u8 = @splat(..)` (`**` não compila em 0.17.0,
  nem `[2]u8{1,2} ** 2`). Semântica idêntica (preenchimento).
- `zig fmt`: 7 arquivos (`root`, `interaction`, `layout`,
  `text_input`, `text_edit`, `text`, `bench/headless`).

## Validação (Zig 0.17.0 real)

- `zig fmt --check`: PASS.
- `zig build test -Doptimize=Debug`: compila; 203/208 passam, 5 falham.
- `zig build test -Doptimize=ReleaseFast`: idem (203/208).
- `zig build integration` Debug e ReleaseFast: PASS.
- `zig build bench -Doptimize=ReleaseFast`: PASS (números no log).
- `tools/test_validate_zig_017.sh` (mockado): PASS.

Falhas restantes (lógica pré-existente, não introduzidas aqui;
não alteradas nesta etapa por recuo consciente):

1. `stage25_5 label emits text and advances layout` — `OutOfCapacity`
   (`"AA"+"A"` = 3 quads em buffer de 8 vértices/2 quads).
2. `stage27_2 sliderFloatText` — esperado 32 vértices, obtido 28.
3. `layout horizontal region` — esperado 48, obtido 51.
4. `stage28_8 tab skips disabled` — esperado 30, obtido 10.
5. `stage28_8 reverse tab` — esperado 20, obtido 40.

## Próxima prioridade

Investigar as 5 falhas acima (testes vs. implementação) antes de
novas funcionalidades. `tools/validate_zig_017.sh` completo segue
vermelho somente por esses 5 testes.
