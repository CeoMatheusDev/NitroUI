# NitroUI — Etapa 28.55

## Escopo
Regressão para corrupção externa do armazenamento UTF-8 pertencente à engine.

## Alterações
- `src/text_edit.zig`: teste `stage28_55 externally corrupted UTF-8 rejects edits and permits repair`.
- Exercita `validateState`, `insertScalar`, `replaceSelectionScalar` e `deleteForward` sobre sequência UTF-8 inválida.
- Verifica que falhas preservam os bytes, o comprimento, o cursor e a seleção.
- Simula reparo explícito da engine e remoção posterior de um escalar multibyte.

## Contratos
Não modifica API pública, runtime, dependências ou política de alocação.
O teste descreve comportamento esperado, ainda não comprovado com Zig 0.17.0.

## Validação
Scripts Shell e ZIP podem ser verificados independentemente do compilador.
Compilação, testes Zig, integração headless e benchmarks permanecem pendentes sem Zig 0.17.0.
