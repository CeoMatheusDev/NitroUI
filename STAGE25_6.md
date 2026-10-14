# Etapa 25.6 — Benchmark headless de texto

## Escopo
- `bench/headless.zig`: adicionadas duas cargas determinísticas, `text_ascii` e `text_unicode` (U+20AC).
- Cada carga mede o caminho completo de frame, `Context.label`, layout, UTF-8, busca de glifo, emissão e consumo do draw view.
- 64/256/1024/4096 labels; 30 frames de aquecimento e 300 medidos, por carga.
- Memória de geometria com capacidade fixa e reutilizada; um glifo visível por label; valida contagens, textura e batching.
- Sem mudança de API pública ou de versão.

## Limites
- Não mede strings longas, fallback, cliques, engine real ou submissão GPU assíncrona.
- O custo inclui início/fim do frame e verificação do draw view, não apenas o decodificador.
- Valores são específicos do hardware; não inferir desempenho real sem executar.

## Validação
- Arquivos inspecionados e pacote gerado.
- Zig 0.17.0 indisponível no ambiente; compilação, testes e benchmarks **não executados**.
- Antes de integrar: `zig fmt --check build.zig src bench examples`, `zig build test`, `zig build test -Doptimize=ReleaseFast`, `zig build integration`, `zig build bench -Doptimize=ReleaseFast`.
