# NitroUI — Etapa 28.66

## Escopo

Teste de regressão para `Buffer.setCursor`: rejeição atômica de offsets no interior de sequências UTF-8, além do comprimento lógico, dentro da capacidade ociosa e `maxInt(usize)`. A seleção invertida anterior e todos os bytes do armazenamento devem permanecer intactos após cada rejeição. O teste também verifica todos os cinco limites válidos do texto `a€🚀b`, que devem aceitar a movimentação e limpar a seleção.

## Arquivos

- `src/text_edit.zig`: teste `stage28_66 setCursor rejects every non-boundary without clearing selection`.
- `STAGE28_66.md`: registro da etapa.

Nenhuma alteração no runtime, na API pública ou nas dependências. Versão 0.2.0 preservada.

## Validação

O autoteste Shell usa um Zig simulado e **não** valida a compilação dos testes Zig. Compilação Zig 0.17.0, testes reais, integração headless e benchmarks permanecem pendentes.
