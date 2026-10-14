# NitroUI — Etapa 28.54

## Escopo

Adicionado teste de regressão para comprimento lógico (`Buffer.len`) maior que
`storage.len`, simulando corrupção do estado pertencente à aplicação.

O teste exige que `validateState`, `insertScalar`, `replaceSelectionScalar` e
`backspace` retornem `error.OutOfCapacity` sem modificar bytes, cursor ou
seleção. Após reparo explícito de `len`, verifica a retomada da edição.

## Alterações

- `src/text_edit.zig`: um teste novo, sem mudanças no runtime.
- `STAGE28_54.md`: este relatório.

## Validação

Os testes Zig exigem Zig 0.17.0. Se indisponível, não são considerados
executados. Testes Shell e integridade do ZIP são verificados separadamente.

## Riscos

O projeto ainda depende de compilação e testes efetivos com Zig 0.17.0,
integração headless e benchmarks. Versão mantida em 0.2.0.
