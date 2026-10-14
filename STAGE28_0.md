# Etapa 28.0 — Fundamento de foco de teclado

- `interaction.State` mantém `focused_id` e acompanha sua submissão a cada frame.
- `requestFocus(id)` solicita foco explicitamente durante um frame aberto; o ID deve ser submetido por `item()` no mesmo frame.
- Pressionar o botão primário sobre um widget transfere foco para ele.
- `endFrame()` remove o foco se o widget não foi submetido ou se a janela perdeu foco.
- `Context.requestFocus(id)` e `Context.focusedId()` expõem o contrato sem armazenamento novo.
- Dois testes de regressão foram escritos; compilação e execução não realizadas.

Limites: não há navegação Tab, teclas de ativação, foco modal ou editor Unicode nesta etapa. O ID de foco é público em State; mutação direta continua possível e deve ser tratada em endurecimento futuro.
