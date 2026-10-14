# NitroUI — Etapa 28.15: posicionamento do cursor por mouse

- `text.caretOffsetAtX` converte uma coordenada horizontal relativa à origem do texto em offset UTF-8 válido, usando avanços de glifos e pontos médios.
- `Context.inputTextScrolled` usa `result.pressed` para posicionar o cursor no clique, considerando a rolagem persistente anterior e o padding.
- `editor.setCursor` descarta a seleção anterior no clique; seleção por arraste continua pendente.
- Cliques antes/depois do texto selecionam início/fim; fallback de glifos segue `font.resolve`.
- Sem buffers ou alocações adicionais. Complexidade O(n) no clique.
- Teste unitário de hit testing com glifos de larguras diferentes e UTF-8 escrito, mas não executado.
- Zig 0.17.0 indisponível: compilação, testes e benchmarks não executados.
- Limitações: sem seleção por arraste, IME ou grapheme clusters; mudanças no editor podem persistir em falha posterior de desenho.
