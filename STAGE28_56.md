# NitroUI — Etapa 28.56

## Escopo

Teste de integração no `src/text_input.zig` para falha por corrupção UTF-8
no armazenamento pertencente à engine, com recuperação do processamento
ordenado de eventos via `applyTracked`.

## Contrato exercitado

- Eventos anteriores ao erro são contabilizados em `Progress.consumed`.
- A tecla Shift já consumida permanece representada em `Progress.shift`.
- O evento que falha não é consumido; nenhum byte nem estado do editor é alterado.
- Após reparo explícito da memória pela engine, somente o sufixo não consumido
  é reaplicado, sem duplicar eventos anteriores.
- A substituição posterior preserva a validade UTF-8 e limpa a seleção.

## Arquivos

- `src/text_input.zig`: novo teste de regressão entre o processador de eventos e o editor.
- `STAGE28_56.md`: este relatório.

Nenhuma API pública ou implementação do runtime foi alterada. Sem dependências
ou alocações adicionais. Versão mantida em 0.2.0.

## Validação

A execução real dos testes Zig requer o compilador Zig 0.17.0, ausente neste
ambiente. Os scripts Shell podem ser validados independentemente, mas seu
executor simulado não substitui a compilação real.
