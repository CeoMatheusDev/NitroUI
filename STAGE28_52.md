# NitroUI — Etapa 28.52

## Escopo

Adicionado teste de regressão em `src/text_edit.zig` para garantir que
`replaceSelectionScalar` rejeite substituições por valores Unicode inválidos
(surrogate U+D800 e valor acima de U+10FFFF) antes de modificar uma seleção
invertida que abrange um caractere UTF-8 multibyte. O teste compara todo o
armazenamento fornecido pela engine, verifica cursor e âncora, e tenta
novamente a substituição por U+1F680.

## Contratos

- Falhas `InvalidScalar` preservam conteúdo, armazenamento, cursor e âncora.
- Uma substituição válida subsequente reutiliza a seleção original.
- Não foram alteradas APIs públicas, implementação do runtime ou dependências.
- Versão mantida em 0.2.0.

## Validação

Verificações Shell e integridade do ZIP são realizadas durante o empacotamento.
A execução dos testes Zig, compilação e benchmarks requer Zig 0.17.0, que não
está disponível no ambiente desta etapa. As asserções do novo teste não
representam resultados executados.
