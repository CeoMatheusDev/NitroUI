# NitroUI — Contrato de integração com a engine (v0.2.0, Zig 0.17.0)

Este documento é o contrato engine-first da NitroUI. A engine hospedeira
fornece janela, eventos, tempo, GPU e buffers; a NitroUI fornece contexto,
IDs, layout, widgets e draw data. Sem backend obrigatório, sem estado
global mutável, sem alocador no hot path (nenhuma função recebe
`std.mem.Allocator`).

## 1. Inclusão como módulo

```zig
// engine/build.zig.zon
.dependencies = .{ .nitro_ui = .{ .path = "third_party/nitro_ui" } },
```

Requer Zig 0.17.0 (`zig version`). Single-thread; um `Context` por
instância; múltiplos contextos independentes suportados.

## 2. Armazenamento (ownership da engine)

Todo armazenamento pertence à engine e deve permanecer vivo enquanto
anexado. Configuração somente em `idle`; sobreposição é rejeitada com
`OverlappingBuffers`:

| Anexo | API | Vida útil |
|---|---|---|
| Geometria tipada | `setGeometryStorage(vertices, indices, commands)` | vida do contexto |
| Estados persistentes | `setStateStorage([]widget_state.Entry)` | vida do contexto |
| Arenas | `setBuffers(scratch, render)`, `setPersistentBuffer` | vida do contexto |
| Diagnóstico de IDs | `setInteractionIdStorage(?[]ids.Id)` | até destacar |
| Navegação | `setNavigationStorage(previous, current)` (disjuntos, mesmo nulidade) | até destacar |

Categorias: `persistent` (contexto/estados/estilos), `scratch` (transitório
de frame), `render` (vértices/índices/comandos). `ByteArena` nunca aloca;
`OutOfCapacity` em vez de crescer. Manutenção de estados explícita via
`pruneStates(min_frame)` em `idle` — nunca implícita no hot path.

## 3. Ciclo de frame

```text
idle → beginFrame → building → endFrame → ready → releaseFrame → idle
```

1. `beginFrame(.{ .delta_seconds, .display_size })` — valida tempo,
   display e posição de mouse; `InvalidFrameState` fora de ordem.
2. `processEvents(&events)` — única fonte de input por padrão
   (`use_mouse_snapshot=false`); pressionar+soltar no mesmo frame gera
   clique imediato.
3. Submissão de widgets em ordem determinística (`widgetId`/`pushId`,
   `interact`, widgets, `pushLayout`/`popLayout`, `pushClip`/`popClip`).
4. `endFrame()` — valida pilhas (IDs/clip/layout) e publica a geometria.
5. `drawDataView()` — somente em `ready`, antes de `releaseFrame()`.
   Revalida contadores e cobertura de comandos; nunca faz trap em
   contadores públicos corrompidos.
6. Renderer consome **sincronamente**, depois `releaseFrame()`.

Chamadas fora de ordem retornam erro documentado (`InvalidFrameState`,
`MissingGeometry`, `MissingStorage`); sem corrupção silenciosa.

## 4. Draw data (contrato de renderização)

- `Vertex` (`extern struct`): `x,y,u,v: f32`, `color: u32` RGBA8 numérico
  `0xAABBGGRR`. Origem top-left, pixels lógicos de display.
- Índices `u32`; `Command{ first_index, index_count: u32, texture: u64,
  clip: ClipRect }`. Comandos cobrem `[0, index_count)` de forma contígua
  e ordenada (verificado em `drawDataView`).
- `texture: u64` é handle opaco da engine (0 = sem textura); comandos só
  agrupam (`merge`) mesma textura **e** mesmo clip.
- Slices de `draw.View` são emprestados: válidos somente em `ready`,
  antes de `releaseFrame()`; a engine não deve mutá-los nem retê-los.
  Prefira `drawDataView()`; `drawData()` é legado.
- Overflow: `OutOfCapacity` (cheio), `IndexOverflow` (> maxInt(u32)),
  `InvalidClip`/`InvalidGeometry` (não-finito, intervalo invertido).
  Falhas de append são atômicas — sem geometria parcial visível.

## 5. Input, foco e texto

- Eventos: `pointer_move`, `pointer_button`, `key{ code, down, repeat }`,
  `text` (scalar), `focus`, scroll. Códigos de navegação reservados
  (Tab/Shift/Enter/Espaço); demais códigos são da aplicação.
- Foco persiste somente enquanto o widget é submetido por frame; Tab usa
  a ordem do frame anterior com recuperação direcional em `endFrame`.
- Texto: UTF-8 estrito (`decodeOne` rejeita overlong/surrogates/>U+10FFFF);
  `measure`/`emitBaseline` sem alocação; `Font` exige glifos ordenados +
  `validate()`; fallback opcional. Sem quebra de linha/multilinha (adiado
  ao layout), sem clipboard/IME/undo.

## 6. Limites conhecidos (v0.2.0)

Sem radio/progress/separator/containers/scroll; `Style` só dark/light e
espaçamentos reservados (widgets usam bounds do chamador); sem GPU real
validada — somente integração headless (`examples/engine_host.zig`).
