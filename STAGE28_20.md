# Etapa 28.20 — progresso explícito em lotes de eventos

## Escopo

`src/text_input.zig`: adicionado `Progress` e `applyTracked()` para reportar quantos eventos foram completamente processados, quantas operações alteraram o texto e os estados finais de Shift/foco, inclusive quando uma operação falha. `apply()` permanece compatível e delega à nova função.

Uma falha de edição preserva o evento que falhou como não consumido; eventos anteriores podem ter alterado o editor. A aplicação deve decidir se descarta, corrige ou tenta novamente o evento que falhou, **sem reproduzir o prefixo consumido**. Uma operação individual de edição permanece atômica, não o lote.

Perda de foco cancela Shift para evitar modificador obsoleto após retorno do foco. Eventos repetidos (`key.down=true, repeat=true`) são processados como eventos normais. A engine fornece eventos ordenados e os estados iniciais corretos.

## Testes escritos

- Erro de capacidade no segundo evento, progresso correto e retomada de sufixo.
- Perda/retorno de foco, Shift resetado e repetição de tecla.

## Memória e complexidade

Sem alocações novas; estado `Progress` do chamador, O(1) de memória. Custo de processamento O(eventos × custo de edição). Nenhum benchmark executado.

## Validação e riscos

Compilação/testes Zig 0.17.0 e integração com engine não executados neste ambiente (compilador indisponível). A API de widget de alto nível ainda usa `apply()` e não expõe progresso parcial; a engine pode utilizar `applyTracked()` diretamente para recuperação explícita. Nenhum contrato público existente foi removido ou alterado. Versão 0.2.0 preservada.
