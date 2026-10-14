# Etapa 26.3 — Dimensionamento proporcional explícito

- `layout.Stack.nextWeighted(weight, remaining_weight, future_items, cross_size)` divide o espaço restante do eixo principal por pesos.
- `Context.nextWeightedLayoutRect(...)` valida o estado `building`.
- O chamador informa o peso total ainda não consumido e a quantidade de irmãos futuros para reservar espaçamento; não há medição antecipada ou reflow.
- Para pesos [1,2,1], chamar respectivamente (1,4,2), (2,3,1), (1,1,0) nos primeiros três argumentos.
- A API usa cálculo intermediário `f64` para reduzir erro de arredondamento e verifica entradas inválidas antes de alterar o cursor.
- Sem alocação dinâmica, sem alteração de APIs existentes, sem dependências.
- Testes novos cobrem divisão horizontal, vertical, reserva de spacing, erro atômico e estado do frame.

## Limitações

- O contrato pressupõe que `future_items` descreve todos os próximos irmãos, incluindo itens fixos; estes últimos ainda exigem que o chamador reserve sua dimensão explicitamente fora da distribuição de pesos.
- A operação não cria sistema de layout flex nem modifica dimensões de irmãos anteriores.
- Compilação, testes e benchmarks Zig 0.17.0 **não executados**: compilador ausente neste ambiente.
