# Etapa 24.1 — Atomicidade lógica dos widgets

- Checkpoint de contadores de geometria, último draw command e estado de interação antes da submissão.
- Rollback em erros de `button`, `checkbox` e `sliderFloat`, preservando valores do chamador.
- Nenhuma API pública alterada; nenhuma alocação dinâmica adicionada.
- Dados escritos além dos contadores após rollback não são expostos por `vertexSlice`/`indexSlice`.
- A restauração é lógica, não um apagamento físico da memória de cauda.
- Testes novos: falha de capacidade em checkbox após primeira primitiva, button e slider.
- Validação Zig 0.17.0 ainda pendente no Fedora.
