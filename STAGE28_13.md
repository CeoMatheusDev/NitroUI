# Etapa 28.13 — Clipping interno do campo de texto

## Escopo
`Context.inputText` agora intersecta o clip fornecido pela engine com a área interna do campo, descontando o padding horizontal. Texto, seleção e cursor usam esse clip; o fundo mantém o clip externo. Interseções vazias resultam em clip de área zero. São validados limites finitos e ordenação do clip antes da interação.

## Testes adicionados
Dois testes para interseção e clip inválido/disjunto. Não executados sem Zig 0.17.0.

## Limitações
Sem rolagem horizontal, posicionamento de cursor por mouse, IME ou grapheme clusters. Não há garantia de rollback da edição se o desenho falhar. Compilação e benchmarks pendentes.

## Versão
0.2.0; sem dependências adicionais, sem publicação remota.
