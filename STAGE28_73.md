# Etapa 28.73 — Auditoria e contrato de integração

Linha de base revalidada neste ambiente antes de qualquer alteração:
Zig 0.17.0, `tools/validate_zig_017.sh` com 6/6 PASS (fmt, testes
Debug/ReleaseFast 208/208, integração Debug/ReleaseFast, bench).
Nenhum arquivo `src/` foi modificado nesta etapa.

## 1. Matriz de auditoria

| Subsistema | Estado | Problemas | Prioridade | Ação necessária |
|---|---|---|---|---|
| Contexto/frame (`root.zig`) | Completo | `drawData()` legado duplica `drawDataView()`; `FrameState` sem `Uninitialized` explícito | Baixa | Deprecar `drawData()`; documentar (28.89) |
| Input (`input.zig`) | Completo | Cobertura boa (press/release no mesmo frame, repeats, perda de foco) | Baixa | Fuzzing (28.88) |
| IDs/estados (`ids.zig`, `state.zig`) | Completo | Retenção exige `pruneStates` manual; sem teste de estresse 10k widgets dinâmicos | Média | Teste de estresse + política documentada (28.77) |
| Geometria/draw (`draw.zig`) | Completo | Sólido: preflight, atomicidade, batching conservador | Baixa | Manter |
| Clipping (`clip.zig`) | Completo | — | Baixa | Cobertura via integração (28.75) |
| Layout (`layout.zig`) | Parcial | Sem containers/scroll; alinhamento/pesos existem mas sem widget consumidor | Alta | Auditoria dedicada (28.78) |
| Interação/navegação (`interaction.zig`) | Completo | O(n²) só na recuperação; sem teste multi-contexto | Média | Testes multi-contexto (28.77) |
| Texto/fontes (`text.zig`, `font.zig`) | Parcial | Sem multilinha/quebra; sem atlas (métricas + UVs da engine) | Alta | Auditoria dedicada (28.79) |
| Edição (`text_edit.zig`, `text_input.zig`) | Completo p/ escopo | Sem clipboard/IME/undo (fora de escopo v1) | Baixa | Declarar escopo (28.80) |
| Widgets (`root.zig`) | Parcial | label/button/checkbox/slider/inputText ok; sem radio/progress/separator/containers | Alta | Consolidação (28.80–28.84) |
| Estilos (`style.zig`) | Parcial | Só dark/light; espaçamentos não consumidos por widgets | Média | Sistema de estilos (28.81) |
| Memória (`memory.zig`) | Completo | Zero-alloc estrutural (nenhum `Allocator` no código); sem teste instrumentado de regressão | Média | Teste de regressão sem-alloc (28.76) |
| Exemplos (`engine_host.zig`) | Parcial | Só button/checkbox/slider, sem texto/foco/erro | Alta | Exemplo ciclo completo (28.74) |
| Bench | Completo p/ escopo | Sem casos interativos/texto-edit; sem linha de base 100/1k/10k widgets contrasts | Média | Benchmarks (28.85) |
| Build/CI | Completo | `validate_zig_017.sh` + CI espelham; ok | Baixa | Manter |

Evidências: `grep` por `Allocator|ArrayList|HashMap` em `src/bench/examples`
retorna vazio; 14 módulos, ~7,6k linhas; API pública em `src/root.zig:5-17`
(reexports) e `Context` (~60 métodos); sem `catch unreachable` para erros
recuperáveis; sem estado global.

## 2. Achados principais

1. Fundamentos (contexto, input, IDs, geometria, UTF-8, edição) estão
   completos e testados; nenhum bug encontrado na auditoria.
2. Lacunas reais: containers/scroll, radio/progress/separator, multilinha,
   exemplo com texto, teste multi-contexto, prova instrumentada de
   zero-alloc.
3. Nenhum risco de segurança novo: buffers da engine, disjunção verificada,
   contadores revalidados, erros em vez de traps.

## 3. Arquivos (etapa 28.73)

| Arquivo | Alteração |
|---|---|
| `docs/integration_contract.md` | Novo: contrato engine-first (armazenamento, ciclo, draw data, input, limites) |
| `build.zig.zon` | `.paths` inclui `docs` (contrato embarca no pacote) |
| `STAGE28_73.md` | Este relatório |
| `src/`, demais | Preservados |

Versão 0.2.0 mantida. Sem dependências, sem mudança de API.

## 4. Validação

Pós-alteração: `zig fmt --check` PASS; `zig build test` (Debug/ReleaseFast),
`zig build integration` (Debug/ReleaseFast) e `zig build bench` via cache
verde; `validate_zig_017.sh` completo reexecutado na linha de base.

## 5. Próxima etapa

28.74: exemplo de integração com ciclo completo (texto, foco, erros,
buffers pequenos), sobre o contrato aqui definido.
