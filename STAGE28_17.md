# Etapa 28.17 — Consolidação da captura durante seleção por mouse

## Alteração

`inputTextDraggedInternal` agora invalida a âncora de arraste quando a janela perde foco, o botão primário é liberado (inclusive fora do campo) ou o widget deixa de possuir a captura. A seleção por arraste continua funcionando com o ponteiro fora dos limites enquanto a captura permanece válida.

A verificação é isolada em `dragCaptureValid`, sem buffers, heap, estado global ou alteração de assinaturas públicas. Dois testes unitários verificam a política de captura/liberação.

## Limites

A âncora ainda pertence à aplicação. Se o widget não for submetido em determinado frame, a aplicação deve reinicializar a âncora antes de reutilizá-lo, pois a NitroUI não pode limpar um ponteiro que não recebeu. A edição textual continua não transacional perante falhas posteriores de renderização. Não há autoscroll contínuo durante o arraste.

## Validação

Os testes foram adicionados, mas não executados: Zig 0.17.0 indisponível. Não há benchmarks nem validação em engine real. Versão mantida em 0.2.0.
