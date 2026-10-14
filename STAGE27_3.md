# Etapa 27.3 — Auditoria dos checkpoints de widgets

## Alteração

`Context.checkpointWidget()` agora valida os três contadores públicos de geometria contra as capacidades dos buffers antes de capturar o último draw command ou permitir a execução de um widget. Contadores inconsistentes retornam `error.OutOfCapacity` sem modificar interação, IDs ou geometria. A verificação é O(1) e não aloca memória.

## Teste de regressão

`stage27_3 widget checkpoint rejects corrupted public geometry counts` exercita contadores inválidos de comandos, vértices e índices, verifica ausência de mutação e confirma recuperação após a correção dos contadores.

## Limitações

- Não foi possível executar Zig 0.17.0 neste ambiente; código e testes aguardam compilação, formatação e execução.
- A validação é apenas dos limites dos contadores; não verifica a consistência semântica de índices ou comandos já presentes.
- As etapas anteriores também permanecem pendentes de validação real. Não publicar como release validada.
