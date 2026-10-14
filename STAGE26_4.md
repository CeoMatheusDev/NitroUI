# Etapa 26.4 — Consolidação dos contratos de layout

## Escopo

Revisão pontual de `src/layout.zig`, sem novas APIs públicas, dependências ou alterações de versão.

## Correção

`Stack.pop()` agora rejeita `depth > max_depth` com `error.StackUnderflow`, preservando o valor corrompido para diagnóstico. Antes, decrementava um contador inválido e podia transformá-lo silenciosamente em um índice aparentemente válido. `reset()` continua sendo a operação explícita de recuperação.

## Testes de regressão adicionados

- Composição aninhada horizontal/vertical com distribuição proporcional e preservação do cursor do pai.
- Atomicidade de erros de peso, reserva extrema de espaçamento e dimensão transversal inválida.
- Profundidade corrompida rejeitada por `pop()` e recuperação explícita por `reset()`.
- Profundidade máxima, overflow da pilha e posicionamento na região mais interna.

## Memória e complexidade

Nenhuma alocação ou buffer novo. Operações continuam O(1) por item, com pilha fixa de 32 regiões.

## Validação

Código e testes escritos; **compilação e execução não realizadas**: compilador Zig 0.17.0 não disponível neste ambiente. Não há resultados de benchmark. Executar `zig fmt build.zig src bench examples`, `zig build test --summary all`, `zig build test -Doptimize=ReleaseFast --summary all` e `zig build integration` antes de integrar.

## Limites conhecidos

Os testes não substituem integração com engine real; o dimensionamento ponderado exige planejamento explícito de pesos e espaçamento futuro. Permanecem pendentes teclado, foco, entrada de texto e widgets adicionais para uso profissional.
