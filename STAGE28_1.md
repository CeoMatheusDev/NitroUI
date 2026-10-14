# Etapa 28.1 — Ativação de botões por teclado

- `input.NavigationKey`: códigos lógicos reservados `enter=13`, `space=32`, `tab=9`. A engine deve mapear seus códigos físicos; `tab` ainda não realiza navegação.
- `interaction.State.keyboardActivate`: retorna ativação apenas para ID focado já submetido, mediante borda `keyPressed` de Enter ou Espaço. Repetição não ativa novamente; janela sem foco não ativa.
- `Context.button` e `Context.buttonText` combinam clique por ponteiro com ativação por teclado, sem alterar assinaturas.
- Teste unitário cobre foco, submissão, ativação única, ID diferente e perda de foco.

## Limitações e pendências

Não há navegação Tab/Shift+Tab, nem tratamento de consumo global de teclas. A aplicação deve traduzir códigos físicos aos códigos lógicos. A ativação só é feita para botões; checkbox e slider continuam com interação anterior. Compilação, testes e benchmarks **não foram executados**: Zig 0.17.0 indisponível no ambiente. A etapa não deve ser publicada como validada.
