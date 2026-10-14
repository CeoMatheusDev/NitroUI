# NitroUI — Etapa 28.36

## Escopo

Teste de regressão para substituição UTF-8 com seleção invertida e capacidade exata, seguido de inserção multibyte que deve falhar atomicamente.

## Arquivos

- `src/text_edit.zig`: um teste novo; runtime preservado.
- `STAGE28_36.md`: este relatório.

## Invariantes exigidos pelo teste

- Seleção invertida `[1,5)` sobre `a€b` é substituída por U+1F680 sem alocação.
- O resultado `a🚀` tem cinco bytes, cursor no limite e seleção nula.
- Inserção posterior de U+20AC com apenas um byte livre retorna `OutOfCapacity` sem modificar o editor.
- `validateState()` aceita o estado após as duas operações.

## Validação

O teste foi escrito, **não executado**: compilador Zig 0.17.0 indisponível neste ambiente. Integridade do ZIP e inspeção estrutural não comprovam compilação ou aprovação de testes. Versão preservada: 0.2.0. Nenhuma publicação remota.
