# Etapa 28.5 — IDs duplicados no armazenamento de navegação

## Problema
Quando o armazenamento opcional `visited_ids` não era configurado, o mecanismo de navegação podia aceitar duas submissões do mesmo ID caso o item não estivesse ativo ou em hover. Isso tornava ambígua a ordem de navegação e podia causar foco inconsistente.

## Alteração
Em `interaction.State.item`, o slice `navigation_current[0..navigation_count]` agora é consultado para detectar IDs repetidos antes de qualquer registro. Uma contagem maior que a capacidade é rejeitada antes de criar o slice. A assinatura pública não mudou e o caminho sem armazenamento de navegação permanece inalterado.

## Testes escritos
- IDs duplicados sem armazenamento de diagnóstico: rejeição atômica e recuperação no mesmo frame.
- Contador de navegação corrompido: rejeição antes de acessar o slice e recuperação após correção.

## Memória e custo
Sem alocações. Quando navegação está habilitada, a verificação adiciona busca linear O(n) por widget, potencialmente O(n²) por frame. É uma medida de correção, não uma otimização; o custo deverá ser medido antes de ampliar para milhares de widgets. Sem navegação configurada, nenhum custo adicional.

## Validação
Revisão estática e integridade do ZIP verificadas. Compilação, testes Zig 0.17.0 e benchmarks **não executados** (compilador indisponível). Versão 0.2.0 preservada; sem publicação remota.

## Pendências
Elegibilidade de widgets desabilitados, foco em listas mutáveis, comportamento de navegação após remoção e testes reais de engine. Antes de novos recursos, executar `zig fmt`, `zig build test`, `zig build integration` e benchmarks em Zig 0.17.0.
