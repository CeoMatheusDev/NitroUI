# NitroUI — Etapa 28.53

## Escopo

Teste de regressão para substituição UTF-8 que aumenta o comprimento do texto até a capacidade exata do armazenamento fornecido pela engine, preservando um sufixo multibyte.

## Alterações

- `src/text_edit.zig`: teste `stage28_53 growing replacement preserves multibyte suffix at exact capacity`.
- Sem alterações de runtime, API pública, dependências ou versão (`0.2.0`).

## Contrato verificado pelo teste

Entrada `aX€b` (6 bytes), seleção invertida do `X` e substituição por `🚀` (4 bytes). Saída esperada `a🚀€b` (9 bytes, capacidade exata), cursor 5, sem seleção. Navegação subsequente deve alcançar os offsets UTF-8 8 e 9.

## Validação

O teste Zig foi escrito, mas **não executado**: compilador Zig 0.17.0 indisponível no ambiente. O autoteste Shell do validador e a integridade do ZIP são verificados separadamente e não constituem validação do runtime.

## Pendências

Compilação, testes Debug/ReleaseFast, integração headless e benchmarks reais com Zig 0.17.0. Não há evidência suficiente para classificar a biblioteca como pronta para interfaces profissionais.
