# Etapa 27.2 — Slider com legenda e valor

- `Context.sliderFloatText`: legenda UTF-8 na parte superior, slider interativo abaixo, valor formatado com duas casas decimais à direita.
- Reutiliza `sliderFloat`, `text.measure` e `drawTextBaseline`; buffer de formatação de 64 bytes na stack, sem alocações dinâmicas.
- Rollback do estado de interação, geometria e valor do chamador em falhas de emissão.
- Dois testes adicionados: renderização e falha/recuperação.
- Limitações: largura da legenda não é automaticamente truncada; fonte precisa oferecer glifos para dígitos, ponto e sinal (ou fallback); a formatação de valores extremos pode exceder o buffer fixo e retornar `InvalidGeometry`.
- Validação: Zig 0.17.0 indisponível neste ambiente; compilação, testes e benchmarks não executados.
- Versão preservada: 0.2.0; não publicado no GitHub.
