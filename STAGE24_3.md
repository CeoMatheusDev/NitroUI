# Etapa 24.3 — Segurança dos buffers

- Centralização da validação dos contadores e da capacidade em `draw.Buffer.preflight`.
- As primitivas `addRect`, `addTriangle`, `addCircle`, `addRoundedRect` e `addLine` (via `addQuad`) verificam os contadores antes de subtrair capacidades ou acessar comandos.
- Rejeição de inconsistência entre o fim do último draw command e `index_count` com `error.InvalidGeometry`.
- Dois testes de regressão para contadores públicos inválidos e comandos inconsistentes.
- Sem mudança de assinaturas públicas, dependências ou alocações.

## Limitações

A checagem não valida todos os comandos anteriores, nem a integridade de todos os índices escritos por código externo. Contadores e slices públicos continuam sendo mutáveis por compatibilidade. A segurança completa pressupõe que o chamador não modifique os buffers diretamente durante a construção. A compilação e os testes Zig 0.17.0 devem ser executados no Fedora.
