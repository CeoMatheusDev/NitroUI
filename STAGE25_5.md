# Etapa 25.5 — Label básico

Adicionada a API `Context.label(font_data, utf8, scale, color, clip_rect)`, que reserva espaço no layout vertical e emite a geometria de texto existente. Retorna o retângulo reservado. É um elemento não interativo: não consome IDs nem estados persistentes.

## Contratos

- Exige frame `building`, storage de geometria e layout ativo.
- A engine mantém ownership de fonte, atlas e buffers.
- O layout é restaurado em caso de falha, inclusive `OutOfCapacity`; a emissão de texto restaura os contadores de geometria e o último comando.
- Nenhuma alocação dinâmica introduzida.
- Texto permanece single-line; wrapping, shaping, kerning e rasterização estão fora do escopo.

## Arquivos

- `src/root.zig`: método `label` e dois testes.
- Demais fontes preservadas; versão permanece 0.2.0.

## Validação

Inspeção estática e verificação de integridade do ZIP. Zig 0.17.0 não disponível no ambiente: compilação, testes e benchmarks não executados. Executar a matriz CI no Fedora antes de integrar/publicar.
