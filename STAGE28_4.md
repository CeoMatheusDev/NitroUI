# Etapa 28.4 — Contratos de armazenamento e ciclo de foco

- `setNavigationStorage` rejeita buffers com sobreposição total ou parcial, inclusive subslices do mesmo array, antes de alterar o estado.
- `item` valida a capacidade do destino `navigation_previous` antes de registrar IDs, impedindo que `endFrame` falhe por falta de espaço após submissões aceitas.
- Três testes cobrem aliasing, atomicidade da capacidade e remoção de foco de widget ausente.
- Sem mudanças de assinaturas públicas, alocações dinâmicas ou dependências externas.

## Pendências

- Widgets desabilitados ainda não possuem contrato uniforme de elegibilidade.
- Tab para widget que desaparece durante o frame pode resultar em foco vazio até o frame seguinte; navegação baseada no frame anterior.
- Falta compilação e execução dos testes em Zig 0.17.0, além de integração real com engine.
