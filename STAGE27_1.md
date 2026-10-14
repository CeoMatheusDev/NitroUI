# Etapa 27.1 — Checkbox com texto UTF-8

- Nova API `Context.checkboxText(id, rect, value, caption, font_data, scale, text_color, clip_rect)`.
- Interação em toda a linha, caixa à esquerda e texto com baseline centralizada.
- O booleano pertencente à aplicação só é alterado depois da emissão bem-sucedida de toda a geometria.
- `checkpointWidget` preserva estado de interação, contadores e último comando em caso de erro.
- Dois testes adicionados para geometria e rollback.
- Sem alocações introduzidas, sem dependências ou alterações de versão.

## Pendências

- Compilação e testes Zig 0.17.0 Debug/ReleaseFast não executados: compilador indisponível.
- A legenda pode exceder a largura do retângulo; truncamento e clipping automático de texto não fazem parte desta etapa.
- O renderizador da engine precisa honrar o `clip_rect` e os texture handles.
- Não há validação com engine real nem benchmark novo.
