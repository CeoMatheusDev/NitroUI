# Etapa 28.10 — seleção UTF-8 (núcleo)

Adicionado `anchor: ?usize` ao `text_edit.Buffer` (valor padrão `null`, preservando `init`). APIs: `selection`, `select`, `clearSelection`, `deleteSelection`, `replaceSelectionScalar`, `moveLeftSelecting`, `moveRightSelecting`. Backspace e Delete removem a seleção existente antes de remover um escalar. `setCursor` e movimentações normais descartam a seleção. A seleção é um intervalo de bytes [start,end) com extremidades nos limites de escalares UTF-8, não clusters de grafemas.

A substituição verifica escalar, estado e capacidade antes de modificar bytes. `anchor` é validado junto com cursor. Armazenamento continua pertencendo à aplicação, sem heap. Foram escritos dois testes de regressão. Não foi executada compilação nem teste Zig 0.17.0: compilador indisponível. A integração com eventos de teclado, IME, seleção visual e clipboard ainda não existe.
