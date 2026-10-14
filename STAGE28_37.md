# Etapa 28.37 — Recuperação após correção explícita de cursor inválido

## Escopo

Um teste de regressão em `src/text_input.zig` cobre o ciclo completo de falha de navegação por cursor externo inválido, correção explícita pelo host e retomada somente do sufixo não consumido de eventos. Não altera runtime, APIs ou dependências.

## Contrato testado

1. Editor contém `abc`, mas o host define `cursor = 9` (inválido).
2. Evento de foco é consumido; navegação à esquerda falha com `InvalidCursor`; inserção seguinte não é consumida.
3. O host restaura `cursor = len`, valida o editor e reprocessa `events[consumed..]` com os estados de foco e Shift reportados.
4. O resultado esperado é `abZc`, cursor 3, sem seleção, com dois eventos consumidos e uma alteração na retomada.

O host deve manter os eventos disponíveis e decidir explicitamente quando corrige e reenvia o evento que falhou. Nenhum replay automático é implementado.

## Memória e compatibilidade

Nenhuma alteração no caminho de execução. O teste usa armazenamento local fixo, sem dependências externas. Versão mantida em `0.2.0`.

## Validação

A integridade do ZIP é verificável; o teste não foi executado. O compilador Zig 0.17.0 não foi encontrado no ambiente de execução. Compilação Debug/ReleaseFast, integração e benchmarks permanecem pendentes.
