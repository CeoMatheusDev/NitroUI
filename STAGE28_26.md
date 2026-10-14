# Etapa 28.26 — Invalidação da âncora de arraste em falhas

## Contrato

Depois de `interact()` retornar com sucesso, se `inputTextDragged` ou
`inputTextDraggedTracked` falhar, o checkpoint do widget restaura o estado de
interação e a âncora de arraste externa é invalidada (`null`). Assim, a
aplicação não continua um arraste com uma âncora associada a uma captura
revertida. Falhas de pré-validação (antes de `interact()`) não modificam a
âncora. O conteúdo textual já editado e o progresso dos eventos permanecem
aplicados conforme a política `retain_edits`; o scroll continua sem commit.

## Alterações

- `src/root.zig`: `errdefer` após interação bem-sucedida invalida a âncora
  em erros posteriores; sem novas alocações ou mudanças de assinatura.
- Teste `stage28_26 render failure invalidates caller drag anchor`:
  verifica âncora nula, edição preservada, progresso, rollback de geometria
  e interação em falha por falta de capacidade.

## Validação

A integridade do ZIP é verificada na geração. A compilação e os testes Zig
0.17.0 **não foram executados**, pois o compilador não está disponível.
A compatibilidade sintática e o comportamento permanecem pendentes de
validação com o compilador exato e integração em engine real.
