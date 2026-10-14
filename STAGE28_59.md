# NitroUI — Etapa 28.59

## Escopo

Remoção da segunda validação completa de UTF-8 em `moveLeftSelecting` e `moveRightSelecting`, mantendo uma única chamada a `check()` antes de qualquer mutação. As operações passam a mover diretamente o cursor, preservando a âncora original e os limites de scalar UTF-8. Nenhuma API pública foi alterada.

## Testes adicionados

- Movimentação de seleção sobre `€` e `🚀`, preservação da âncora no limite direito e cancelamento da seleção quando o cursor retorna à origem.
- Corrupção UTF-8 externa: ambos os movimentos rejeitam com `InvalidUtf8` sem modificar estado ou armazenamento.

## Memória e complexidade

Nenhuma alocação nova. Cada movimento continua O(n) pela validação integral do texto; foi removida uma segunda varredura de validação. Não há benchmark demonstrando ganho.

## Validação

Os scripts Shell e seu autoteste com Zig simulado foram executados; os resultados devem ser consultados no relatório da entrega. Compilação, testes Zig e benchmarks reais dependem do compilador Zig 0.17.0, indisponível no ambiente.
