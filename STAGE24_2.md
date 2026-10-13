# Etapa 24.2 — Entrada de mouse consolidada (opt-in)

`FrameInput.use_mouse_snapshot` (padrão `false`) habilita a sincronização de `mouse_position` e `mouse_primary_down` com `input_processor.snapshot` no início do frame. Quando desabilitado, o comportamento anterior baseado exclusivamente em `processEvents()` é preservado.

Quando habilitado, `beginFrame()` atualiza a posição e produz transições de pressionamento/liberação comparando o botão primário com o estado anterior. Eventos subsequentes processados via `processEvents()` são aplicados depois e têm precedência na posição/estado contínuo; transições discretas acumulam no frame.

Coordenadas não finitas com opt-in habilitado retornam `error.InvalidMousePosition` antes de qualquer reset de buffers ou transição de frame.

**Limitações:** snapshots por frame não preservam movimentos intermediários; `processEvents()` continua necessário para texto, scroll, teclado e eventos ordenados. O modo opt-in não modifica foco. Evitar misturar as duas fontes para o mesmo botão quando a engine não controla a ordem dos eventos.

**Validação:** três testes adicionados. Compilação Zig 0.17.0 ainda não executada neste ambiente.
