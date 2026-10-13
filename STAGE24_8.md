# Etapa 24.8 — Auditoria final de memória e contratos

Versão mantida: 0.1.0. Nenhum bump de versão.

## Escopo

Auditoria focada em memória, contratos e invariantes sobre a baseline 24.7,
seguida de correções pontuais justificadas, sem refatoração ampla e sem novas
dependências. Trabalho incremental a partir do código real em `src/`.

## Achados concretos e correções

### A. Armazenamento de diagnóstico de IDs sem validação de overlap (principal)

Causa: `Context.setInteractionIdStorage()` aceitava qualquer slice fornecido
pela engine, e `setGeometryStorage()` / `setBuffers()` / `setPersistentBuffer()` /
`setStateStorage()` não verificavam contra `interaction_state.visited_ids`.
Duas regiões proprietárias da engine podiam aliasar, permitindo que escritas
de geometria corrompessem o tracking (ou vice-versa).

Contrato esperado: todo armazenamento proprietário da engine deve ser disjunto;
falha de configuração retorna `error.OverlappingBuffers` sem mutar o contexto.

Correção (`src/root.zig`):
- `setInteractionIdStorage()` valida o novo slice contra scratch, render,
  persistent, state entries e os três buffers de geometria antes de delegar.
- `setGeometryStorage()`, `setBuffers()`, `setPersistentBuffer()` e
  `setStateStorage()` validam contra o `visited_ids` já configurado.
- Todas as falhas preservam a configuração anterior (transacional).

### B. `drawDataView()` podia travar em contadores corrompidos

Causa: `draw.Buffer.view()` fatia `vertices[0..vertex_count]` sem validar.
Como `Context.geometry` é campo público, uma mutação externa dos contadores
fazia `drawDataView()` executar slice OOB (panic em Debug, UB em ReleaseFast).

Contrato esperado: leitura em `ready` nunca executa OOB; contadores inválidos
retornam erro e preservam o estado `ready`.

Correção (`src/root.zig`): `drawDataView()` revalida limites, `maxInt(u32)` e
cobertura contígua dos comandos antes de fatiar. Assinatura alargada de
`Error!View` para `(Error || draw.Error)!View` (compatível com chamadores que
usam `try`; mesmo padrão já usado por `drawRect` e demais primitivas).

### C. `visited_count` corrompido causava panic em `item()`

Causa: `storage[0..visited_count]` sem verificar `visited_count <= len`.

Correção (`src/interaction.zig`): guarda `if (visited_count > len) return
IdTrackingCapacity` antes do loop. Mesmo erro já existente, sem mudança de API.

### D. Pilhas aceitavam `depth` corrompido com OOB em ReleaseFast

Causa: pushes testavam `depth == limite` em vez de `>=`, e leituras
(`current`, `next`) não verificavam `depth > capacidade`.

Correções sem mudança de API (mesmas variantes de erro, apenas mais casos):
- `src/ids.zig`: pushes usam `>=`; `current()` retorna `offset_basis` se
  `depth > max_depth` (evita OOB; mutação direta continua sendo violação).
- `src/clip.zig`: push usa `>=`; `current()` retorna `null` se
  `depth > capacity` (vira `InvalidClip` no contexto).
- `src/layout.zig`: push usa `>=`; `next()` retorna `StackUnderflow` se
  `depth > max_depth`.
- `src/memory.zig`: `remaining()` satura em 0 quando `used >= len`.

## Testes de regressão (8 novos, total 79)

- `src/root.zig`: overlap de ID tracking nas duas ordens de configuração
  (geometria e arenas/state), transacionalidade, detach/reattach; `drawDataView`
  com contadores e comando corrompidos.
- `src/interaction.zig`: `visited_count` corrompido retorna `IdTrackingCapacity`.
- `src/ids.zig`, `src/clip.zig`, `src/layout.zig`: `depth` corrompido sem OOB.
- `src/memory.zig`: `remaining()` saturado com cursor corrompido.

## Validação executada (Zig 0.17.0, Linux)

```sh
zig fmt build.zig src bench
zig fmt --check build.zig src bench
zig build test --summary all        # 79/79 passed
zig test src/root.zig               # 79/79 passed
zig build bench -Doptimize=ReleaseFast
```

Benchmark determinístico inalterado (checksums 192300 / 768300 / 3072300 /
12288300), acrescido das métricas de capacidade da etapa 24.7. Nenhuma medição
de latência foi introduzida; continua pendente um harness temporal com
warm-up e estatísticas, sem acoplar relógio ao módulo NitroUI.

## Riscos residuais / não alterado

- Mutação direta de campos públicos do `Context` (ex.: `ctx.geometry`,
  `ctx.id_stack.depth`) fora da API continua sendo violação contratual; o
  endurecimento acima elimina UB nos caminhos auditados, mas a disciplina de
  usar apenas os métodos do contexto permanece obrigatória.
- `widgetState()` sem `setStateStorage()` continua retornando `OutOfCapacity`
  (conflação conhecida entre "não configurado" e "cheio"); mudança do erro
  foi adiada para evitar churn de API antes da 0.2.0.
- `processEvents()` não valida overlap do slice de eventos contra geometria/
  arenas; eventos são transitórios por frame e a engine não deve aliasá-los,
  mas uma verificação por batch pode ser avaliada se houver evidência de risco.
- Meta de zero alocações após warm-up segue não demonstrada
  experimentalmente em todos os hot paths; sem `comptime`/SoA especulativos.
