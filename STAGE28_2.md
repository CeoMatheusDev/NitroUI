# Etapa 28.2 — Navegação por Tab

Adicionado armazenamento explícito de duas listas de IDs pertencentes à engine: ordem do frame anterior e ordem do frame atual. `Context.setNavigationStorage(previous, current)` configura o mecanismo fora de frames; `Tab` e `Shift+Tab` selecionam o próximo/anterior ID usando a ordem do frame anterior, com wrap-around. A engine mapeia Shift para código lógico 16. Sem alocações. O foco continua sendo descartado se o ID selecionado não aparecer no frame atual.

## Limitações e validação

Navegação habilitada somente quando os dois buffers são configurados; todos os itens submetidos por `interact` entram na ordem. Ainda não há política de `disabled`, nem seleção por acessibilidade. Compilação e testes Zig 0.17.0 **não executados** (compilador indisponível). O teste cobre avanço e retrocesso. Antes de integrar, executar testes Debug/ReleaseFast, verificar capacidade e eventuais erros de compatibilidade.
