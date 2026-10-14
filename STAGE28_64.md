# NitroUI — Etapa 28.64

## Escopo

Cobertura de fronteiras de codificação UTF-8 e rejeição atômica de escalares Unicode inválidos no editor de texto. Sem alterações de API ou runtime.

## Alterações

- `src/text_edit.zig`: teste com dez valores escalares nos limites de codificação UTF-8 (1–4 bytes), incluindo NUL, U+D7FF, U+E000 e U+10FFFF, verificando bytes exatos, cursor e estado.
- `src/text_edit.zig`: teste de quatro valores inválidos (surrogates e acima de U+10FFFF) em substituições de seleção, exigindo preservação integral do armazenamento e dos metadados.

## Validação

- Executar `sh tools/validate_zig_017.sh` em ambiente com Zig 0.17.0 para compilação, testes, integração headless e benchmark.
- Os testes Zig não foram executados neste ambiente devido à ausência do compilador.
- Testes de scripts Shell com Zig simulado não equivalem à validação do código Zig.

## Limitações

A suíte não substitui fuzzing, sanitização, integração real e benchmarks. A versão permanece 0.2.0.
