# Etapa 28.8 — Recuperação direcional de foco

- Quando o alvo de Tab desaparece ou é desabilitado no frame corrente, `endFrame` procura o próximo ID elegível na ordem anterior, respeitando Tab/Shift+Tab e wrap-around.
- A busca usa os buffers já fornecidos pela engine, sem alocações; no pior caso, O(n²) por recuperação, fora do caminho comum.
- Se nenhum sucessor anterior estiver elegível, usa o primeiro/último elegível atual. Se não houver elegíveis, remove o foco.
- A recuperação acontece no encerramento do frame, sem ativação retroativa.
- Acrescentados testes para salto de item desabilitado no meio da sequência, em ambas as direções.

## Limitações

- A lógica ainda depende de uma ordem anterior válida e de IDs únicos nos buffers de navegação.
- O subsistema de navegação e os widgets ainda precisam de compilação e testes reais com Zig 0.17.0.
- Não há integração com engine real nem benchmarks executados nesta etapa.
