# NitroUI — Etapa 28.65

## Escopo

Regressão para seleção UTF-8: endpoints inválidos dentro de escalares multibyte, além do comprimento lógico e dentro da capacidade ociosa não podem modificar cursor, âncora ou bytes do armazenamento. Após as rejeições, uma seleção válida deve funcionar normalmente.

## Arquivos

- `src/text_edit.zig`: teste `stage28_65 rejected selection endpoints preserve reverse selection and storage`.
- `STAGE28_65.md`: este registro.

Nenhuma API pública ou implementação de produção foi modificada. Versão 0.2.0 mantida.

## Validação

Scripts Shell e autoteste de infraestrutura executados localmente, com Zig simulado. A execução dos testes Zig, compilação real, integração headless e benchmarks dependem de Zig 0.17.0, indisponível neste ambiente.
