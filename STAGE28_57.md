# Etapa 28.57 — Pré-validação e inserção interna

## Alteração

`src/text_edit.zig`: `replaceSelectionScalar` já valida o estado UTF-8, o scalar e a capacidade final antes de remover a seleção. Anteriormente chamava `insertScalar`, que validava novamente o texto após a remoção. Agora as duas operações compartilham a função privada `insertScalarPrechecked`, chamada somente depois das verificações públicas. O contrato público e os erros permanecem iguais.

## Segurança

A substituição valida a capacidade final antes de alterar bytes; a função interna não é exposta publicamente. O deslocamento reverso do sufixo continua sem alocação. Foram adicionados testes para substituição multibyte na capacidade exata e falha atômica seguida de retentativa.

## Performance

A substituição bem-sucedida elimina uma varredura completa de validação UTF-8 após apagar a seleção. Não há benchmark nem alegação de ganho medido. O custo de `check()` na entrada permanece O(n); o deslocamento é O(n).

## Validação

Scripts Shell e autoteste com Zig simulado podem ser executados localmente. Compilação, testes Zig reais e benchmarks exigem Zig 0.17.0 e continuam pendentes neste ambiente.
