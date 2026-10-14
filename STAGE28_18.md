# Etapa 28.18 — Rolagem automática durante seleção por arraste

- `Context.inputTextDragged()` agora atualiza um deslocamento horizontal temporário quando o ponteiro capturado ultrapassa a área interna do campo.
- A velocidade cresce com a distância além da borda, limitada a 1200 pixels/segundo. O delta time fornecido pela engine é limitado a 0,1 s por frame.
- O deslocamento não fica negativo e é gravado somente após renderização bem-sucedida.
- O hit testing utiliza o deslocamento atualizado; a seleção permanece no buffer da aplicação.
- Nenhuma API pública foi alterada, nenhuma dependência ou alocação dinâmica foi adicionada.
- Dois testes unitários adicionados; execução requer Zig 0.17.0.

## Limitações

- O cursor ainda opera por pontos de código Unicode, não grapheme clusters.
- Edição de texto não é transacional com a renderização.
- A velocidade depende da posição do ponteiro e não foi calibrada por testes de usabilidade.
- Sem compilação, testes executados, benchmarks ou integração com engine neste ambiente.
