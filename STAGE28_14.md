# NitroUI — Etapa 28.14: rolagem horizontal do inputText

- Adicionada `Context.inputTextScrolled(...)` com `horizontal_scroll: *f32` persistido pelo chamador.
- `Context.inputText(...)` permanece compatível, utilizando deslocamento temporário de zero por chamada.
- Cursor, seleção e texto compartilham a mesma origem horizontal deslocada; clipping interno da Etapa 28.13 permanece.
- Offset atualizado após a emissão da geometria, evitando commit parcial desse estado em erros de desenho.
- O texto editado ainda pode persistir se uma etapa posterior de renderização falhar; lote de eventos não é transacional.
- A rolagem é calculada pela posição do cursor mesmo sem foco, para não depender da ordem de processamento de eventos.
- Dois testes unitários escritos para posicionamento e valores inválidos.
- Sem alocações adicionais. Medições e testes Zig 0.17.0 não executados (compilador indisponível).
- Pendências: posicionamento do cursor por mouse, seleção por arraste, IME, grapheme clusters e integração com engine.
