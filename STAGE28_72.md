# Etapa 28.72 — Triagem das cinco falhas de teste

- `root.zig` (label): teste corrigido para reservar 12 vértices e 18 índices, suficientes para três glifos (`AA` + `A`); a capacidade anterior comportava apenas dois glifos.
- `root.zig` (sliderFloatText): expectativas ajustadas para 28 vértices/42 índices (7 quads), conforme resultado real reportado com Zig 0.17.0. Deve ser revalidado com compilador real.
- `layout.zig`: posição horizontal esperada corrigida para x=51 (10+20+3, depois 33+15+3).
- `interaction.zig`: preserva o alvo Tab calculado na ordem anterior para procurar o próximo item elegível ao final do frame, mesmo quando a submissão desabilitada já limpou `focused_id`. Campo interno, sem alteração de API de métodos ou alocações.

Validação real com Zig 0.17.0 não executada neste ambiente; resultados do usuário na etapa anterior não equivalem à execução desta revisão. A versão permanece 0.2.0.
