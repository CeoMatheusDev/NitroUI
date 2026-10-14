# Etapa 25.1 — Contratos de fonte e glifo

- Novo módulo público `src/font.zig` exportado por `root.font`.
- Fonte empresta slice imutável de glifos ordenados; textura é identificador opaco pertencente à engine.
- Validação de Unicode scalar, métricas finitas, dimensões não negativas, UV normalizado e ordenação estrita.
- Lookup binário O(log n) e fallback explícito; `find`/`resolve` pressupõem validação prévia.
- Nenhuma alocação, rasterização, geometria ou dependência externa.
- Três testes adicionados; não executados neste ambiente (Zig 0.17.0 indisponível).
- Versão 0.2.0 e demais APIs preservadas.

## Pendências

- Definir escala/tamanho de fonte, posicionamento baseline e quebras de linha antes da geometria.
- A engine deve manter vivos o slice de glifos e o texture handle durante o uso.
- Não modificar os glifos após validação enquanto estiverem em uso.
