# NitroUI 0.1.0 — milestone 3: persistent memory and overlap validation

Engine-first Immediate Mode UI in Zig 0.17.0 (target). No OS, GPU or C dependencies.

## Implemented

- Explicit frame lifecycle: idle → building → ready → idle.
- Caller-owned, fixed-capacity scratch, render, and persistent byte arenas.
- Checked non-overlap validation on buffer attachment (transactional on failure).
- Explicit `OutOfCapacity` and `SizeOverflow`; no heap allocations.
- Failed reservations leave buffer cursors unchanged.
- Render storage remains stable during `ready`; next frame is prohibited until release.
- High-watermark accounting for buffer capacity planning.

## Ownership and limitations

The caller owns and retains all attached storage slices for the entire context lifetime (or until buffers are replaced while idle). `setBuffers` and `setPersistentBuffer` reject overlapping regions; callers must still ensure the underlying storage stays alive and stable. Never modify or resize buffers while a frame is active. Scratch and render storage are byte-oriented and do not guarantee typed alignment. These are foundations, **not** a complete typed vertex/index/command buffer API. Persistent byte storage exists, but widget-state indexing and reclamation are not implemented. Buffer capacity is fixed; overflow returns an error instead of allocating.

## Integration

Copy to `engine/third_party/nitro_ui/`. Integrate its local module via `build.zig`. Provide scratch/render storage with `setBuffers`, and optionally persistent storage with `setPersistentBuffer`, before the first frame. Call `beginFrame`, build (future widgets), `endFrame`, consume render data, then `releaseFrame`.

## Validation

Run `zig build test` with Zig 0.17.0. The compiler is unavailable in this execution environment; code has **not** been compiler-verified. `build.zig.zon` still contains a provisional fingerprint and needs Zig package-manager validation.

## Etapa 4 — reservas alinhadas

`ByteArena.reserveAligned(count, alignment)` permite reservar regiões cujo endereço
inicial é múltiplo de `alignment` (potência de dois, maior que zero). O padding
necessário consome capacidade; a operação é transacional quando falha.
O contexto disponibiliza `reserveScratchAligned`, `reserveRenderAligned` e
`reservePersistentAligned`, exclusivamente durante `building`.

**Validade e ownership:** a engine é proprietária dos três buffers, que não podem
se sobrepor e devem permanecer vivos enquanto associados ao contexto. Scratch
pode ser reutilizado em `beginFrame`; render não deve ser acessado após
`releaseFrame`; persistent permanece reservado até substituição explícita.
A engine deve concluir qualquer leitura assíncrona (inclusive GPU) antes de
permitir a reutilização do buffer render. Nenhuma arena inicializa bytes.

**Política de capacidade:** fixed-capacity, sem crescimento automático. Falhas
retornam `OutOfCapacity`; o chamador pode provisionar buffers maiores somente
quando o contexto estiver `idle`. A substituição invalida slices anteriores.
Reservas alinhadas retornam `[]u8`; não constituem ainda uma API tipada.

**Validação:** testes foram adicionados, mas a compilação e execução em Zig
0.17.0 ainda não foram realizadas neste ambiente.

## Milestone 5 — ordered input events (draft)

`src/input.zig` defines OS-independent event variants and a `Processor` with
continuous pointer/button state and per-frame transitions. The engine supplies
ordered events via `Context.processEvents()` during `building`. Validation is
performed before mutation. Input slices remain caller-owned; do not mutate or
free them while referenced by the context. Multiple batches per frame are
supported, but each batch replaces the exposed `events` slice; accumulated
button transitions and wheel deltas remain in `snapshot`.

**Not yet implemented:** keyboard-held state, text queue persistence across
batches, event timestamps, pointer capture, and stable widget IDs. Wheel sum
can overflow `f32` with extremely large finite inputs; avoid interpreting it
as a validated finite delta until that contract is tightened.

**Validation status:** Zig 0.17.0 compiler unavailable in this environment;
source and tests have not been compiled or executed.

## Milestone 6 — teclado e consistência de input

- Estado de 256 códigos lógicos de tecla (`0...255`), com bitsets para `down`,
  `pressed` e `released`; os códigos são definidos pela engine, não pelo SO.
- Transições de mouse/teclado e scroll acumulam entre lotes no mesmo frame;
  somente `beginFrame` limpa os estados transitórios.
- Processamento transacional: qualquer evento inválido ou overflow de scroll
  rejeita o lote completo sem alterar o snapshot ou o último lote aceito.
- Perda de foco libera teclas e botões pressionados.
- `Processor.events` referencia **somente o último lote**; para processar texto
  de múltiplos lotes a engine deve consumir cada lote antes do seguinte.
- O buffer de eventos continua pertencendo à engine e precisa permanecer válido
  durante seu consumo. A API de texto agregado ainda está pendente.

A compilação e os testes em Zig 0.17.0 permanecem pendentes de execução.

## Etapa 7 — Identificadores hierárquicos

`src/ids.zig` define `Id = u64` e `Stack` com profundidade máxima de 64
escopos, sem heap. Usa FNV-1a de 64 bits, com tags de tipo e prefixo de
comprimento para labels. O hash é determinístico dentro da mesma versão do
algoritmo, mas **não garante ausência de colisões**; IDs não são serializados
nem devem ser usados como identificadores persistentes entre versões.

Durante `building`, utilize `ctx.widgetId("nome")`, `ctx.pushId("escopo")`,
`ctx.pushIdInteger(index)` e `ctx.popId()`. `endFrame()` rejeita escopos
não balanceados, sem avançar o estado do contexto. `beginFrame()` reinicia
a pilha na raiz. IDs iguais dentro do mesmo escopo identificam o mesmo widget:
o chamador deve usar escopos diferentes para instâncias repetidas.

Ainda pendente: detecção opcional de colisões em Debug, associação de estado
persistente a IDs e política de limpeza de estados abandonados.

## Etapa 8 — Estados persistentes por ID (experimental)

`src/state.zig` implementa tabela hash de capacidade fixa, com sondagem linear,
entradas `{ id, value: u64, last_seen, occupied }` e armazenamento tipado
fornecido pela engine. `Context.setStateStorage` configura a tabela em `idle`;
`Context.widgetState(id)` acessa/cria o estado durante `building`.
`Context.pruneStates(min_frame)` faz limpeza explícita em `idle`.

**Contratos:** não modificar o armazenamento externo enquanto estiver anexado;
não manter ponteiros para entradas depois de `pruneStates` ou substituição da
tabela; IDs distintos que colidam no hash da tabela são diferenciados por
comparação integral de `u64`, mas colisões do próprio gerador de IDs continuam
possíveis. O valor `u64` é armazenamento bruto; tipagem e ownership de dados
externos ficam para etapas posteriores. A limpeza pode custar O(capacidade²)
e não ocorre durante a construção de widgets. Não há crescimento automático.

**Validação:** testes adicionados, ainda não executados com Zig 0.17.0.

## Etapa 9 — geometria experimental

`src/draw.zig` implementa buffers tipados, índices `u32`, vértices `RGBA8`,
clip rects e agrupamento somente de comandos adjacentes com textura/clip iguais.
O contexto recebe armazenamento externo via `setGeometryStorage`, constrói
retângulos via `drawRect` e expõe `drawData` somente no estado `ready`.
A engine mantém a posse da memória e deve completar o consumo antes de
`releaseFrame`. Coordenadas em pixels lógicos com origem no canto superior
esquerdo; UV normalizadas. Textura é um identificador opaco `u64`.
A ausência de geometria configurada retorna `MissingGeometry` ao consultar
`drawData` e `OutOfCapacity` ao tentar desenhar. Os buffers de geometria
são separados da arena de bytes de renderização para preservar alinhamento e
simplificar ownership. Ainda não há tesselação genérica, clipping de CPU,
conversão de índices nem integração GPU.

**Validação:** testes foram escritos, mas Zig 0.17.0 não foi executado neste ambiente.

## Etapa 10 — triângulos e consistência de batching

- `draw.Buffer.addTriangle` e `Context.drawTriangle`: triângulos preenchidos, três vértices e três índices.
- Retângulos e triângulos adjacentes podem compartilhar um comando somente se textura, clipping e sequência de índices forem compatíveis.
- `Context.drawRect` agora retorna `MissingGeometry` se os buffers não estiverem configurados.
- A geometria é validada antes de qualquer escrita; falhas não alteram as contagens.
- Não há implementação de linhas, círculos, arredondamento ou clip stack nesta etapa.
- **Validação:** testes adicionados, porém não executados; Zig 0.17.0 indisponível neste ambiente.

## Milestone 12 — Geometry extensions (experimental)

- `draw.Buffer.addLine`: thick line as a quad (4 vertices, 6 indices), rejects zero-length and nonfinite geometry.
- `draw.Buffer.addCircle`: filled triangle fan (segments 3..256), generates `segments + 1` vertices and `3 * segments` indices.
- `Context.drawLine`, `drawCircle`, `drawLineClipped`, `drawCircleClipped`.
- Fixed-capacity engine-owned buffers, atomic preflight, adjacent command merging.
- Clipping is command/scissor based: **geometry is not CPU-clipped**. No visibility culling yet.
- UVs on circles and lines are placeholders; textured rendering of these primitives is not yet defined.
- Zig 0.17.0 compile/test remains unverified in this environment.

## GitHub repository setup

This source archive includes `.gitignore`, a GitHub Actions workflow, and
contribution guidance. See [GITHUB_SETUP.md](GITHUB_SETUP.md) for repository
creation, first push, CI limitations, package fingerprint, and licensing.
