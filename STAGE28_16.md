# Etapa 28.16 — Seleção por arraste

- Adicionada `Context.inputTextDragged(...)` com `drag_anchor: *?usize` pertencente ao chamador.
- Pressionamento posiciona o cursor e define âncora; enquanto a captura primária permanece ativa, a posição do ponteiro atualiza a seleção em limites UTF-8 por `text.caretOffsetAtX`.
- Ao encerrar a captura, a âncora transitória é limpa, mas a seleção no editor é preservada.
- `inputText` e `inputTextScrolled` continuam disponíveis, delegando à implementação comum sem estado de arraste.
- A coordenada do ponteiro considera o scroll horizontal persistente.
- Limitações: a atualização de seleção ocorre enquanto o botão permanece pressionado; não há autoscroll contínuo fora do campo, IME nem suporte a grapheme clusters. Estado de texto e âncora não é transacional perante falhas posteriores de desenho.
- Compilação/testes Zig 0.17.0 e benchmarks: não executados (compilador ausente).
