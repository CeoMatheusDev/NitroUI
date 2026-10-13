# Etapa 25.0 — Auditoria estática da base v0.2.0

Data: 2026-10-13. Baseline: ZIP fornecido pelo usuário (`nitro_ui.zip`).
Versão preservada: `0.2.0`. **Nenhuma API ou arquivo de implementação alterado.**

## Inventário verificado

- `build.zig.zon`: versão 0.2.0, mínimo Zig 0.17.0, dependências vazias; paths: build, src, bench, examples.
- `src/`: root, memory, input, ids, state, draw, clip, layout, interaction, style (10 módulos).
- `bench/headless.zig`, `examples/engine_host.zig`, `README.md`.
- `build.zig`: steps `test`, `bench`, `integration`.
- `Context`: máquina de estados idle/building/ready; `drawDataView()` revalida contadores e sequência de comandos; engine possui buffers.
- Geometria: `Vertex` inclui UV e `Command` inclui handle de textura e clipping. Não existe subsistema de fontes ou texto na base examinada.

## Achados e limites

1. **P0 — fonte de verdade da distribuição:** o ZIP recebido inclui `.zig-cache/` (67 entradas identificadas no inventário) e não é uma distribuição mínima. O pacote desta etapa exclui cache, `.git`, `zig-out` e binários; conferir o arquivo da release remota separadamente caso seja exigida equivalência byte a byte.
2. **P1 — desenho de texto:** ainda não há contrato de glifo, atlas, avanço, baseline, fallback nem decodificador UTF-8. Definir estes contratos antes de escrever geometria ou widget `label`.
3. **P1 — validade do draw data:** `drawDataView()` expõe slices emprestados válidos somente no estado ready, até `releaseFrame()`; renderers assíncronos precisam copiar ou manter os buffers vivos por contrato da engine.
4. **P1 — mutabilidade pública:** `Context.geometry` e os contadores de `draw.Buffer` são publicamente mutáveis; `drawDataView()` valida contadores e encadeamento dos comandos, mas não constitui validação integral de cada índice de vértice. Preservar API nesta etapa e documentar a confiança exigida do chamador.
5. **P2 — layout:** implementação existente é sequencial vertical; texto deverá receber métricas explícitas e política de overflow, sem criar sistema de layout paralelo.
6. **P2 — benchmark:** workloads rect/widget/idstr não cobrem UTF-8, glyph lookup, UVs ou troca de atlas; adicionar cenário específico após a implementação de texto.

## Contrato proposto para 25.1 (requer revisão antes da implementação)

- Atlas e textura pertencem à engine; NitroUI não rasteriza fontes nem acessa GPU/SO.
- Fonte é uma descrição emprestada de glifos e métricas imutáveis durante o frame.
- Coordenadas de glifo e UV em f32 finitos; dimensões e avanços não negativos quando aplicável.
- UTF-8: definir comportamento determinístico para sequências inválidas (erro ou substituição), sem alocação.
- Fallback: política explícita para glifo ausente; sem acesso implícito a recursos externos.
- Saída: quad indexado por glifo visível, respeitando textura, clipping, ordem visual e capacidade.
- Atomicidade: especificar se falha por capacidade reverte toda a string ou apenas o glifo atual; preferir transação completa quando viável.
- Layout: altura de linha, baseline, largura medida, quebras de linha e clipping precisam de semântica definida.
- Benchmark: medir custo de decodificação, lookup e emissão sem misturar rasterização da engine.

## Validação efetivamente realizada

- Extração e inspeção estática do código e dos contratos listados.
- Integridade do ZIP novo deve ser verificada separadamente via `unzip -t`.
- **Zig 0.17.0 não está disponível neste ambiente: compilação e testes não foram executados nesta etapa.**
- Última execução confirmada pelo usuário: 82/82 testes Debug e ReleaseFast e integração headless na etapa 24.20.

## Próximo passo

Etapa 25.1: aprovar contratos mínimos de texto/fontes e adicionar tipos/testes de validação, sem alterar a API pública existente nem o versionamento. Nenhuma publicação no GitHub nesta etapa.
