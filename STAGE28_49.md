# NitroUI — Etapa 28.49

## Escopo

Cobertura de limites da inicialização de `text_edit.Buffer` sem mudanças de runtime:

- Entrada vazia com slice de origem de comprimento zero dentro do armazenamento do chamador. Não há intervalo de memória sobreposto quando não há bytes.
- Falha de capacidade e UTF-8 inválido não alteram o armazenamento do chamador.
- Inicialização UTF-8 de quatro bytes com capacidade exatamente igual ao comprimento inicial.

## Arquivos

- `src/text_edit.zig`: dois testes de regressão.
- `STAGE28_49.md`: este relatório.

## Contratos

Sem mudanças de API, ownership ou alocação. O armazenamento continua pertencendo à engine. A versão permanece 0.2.0.

## Validação

Os testes Zig foram escritos, mas não executados: o compilador Zig 0.17.0 não está disponível no ambiente. Verificações Shell e integridade do ZIP são realizadas separadamente. Não há alegação de compilação ou benchmarks.
