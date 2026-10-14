# Etapa 28.58 — Remoção de validações UTF-8 redundantes

- `src/text_edit.zig`: `backspace()` e `deleteForward()` agora validam o estado uma vez antes de executar remoções; o caminho de seleção compartilha o auxiliar privado `deleteSelectionPrechecked()`.
- `backspace()` percorre o limite UTF-8 anterior diretamente após a validação, sem chamar `moveLeft()` (que validaria o texto novamente).
- `deleteSelection()` mantém seu contrato público de validação, delegando somente a mutação ao auxiliar privado.
- Dois testes verificam remoção multibyte e seleção invertida, com sufixos preservados.
- Sem alterações na API pública, dependências ou alocações. O custo de validação permanece O(n), e a remoção/deslocamento permanece O(n). Nenhum ganho numérico é afirmado sem benchmark.
- Compilação, testes Zig e benchmarks pendentes na ausência do compilador Zig 0.17.0.
