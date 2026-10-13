# Etapa 24.21 — Preparação da release candidate

Versão mantida: 0.1.0. Produção: 2 doc comments (`beginFrame`/`endFrame`),
README (step `integration` + ressalva síncrona), pacote refeito. Sem mudanças
de comportamento.

## 1. Pacote de distribuição

`nitro_ui_milestone24_21.zip` (ao lado do projeto) contém `build.zig`,
`build.zig.zon`, `src/` (10 módulos), `bench/`, `examples/`, `README.md` e
`STAGE*.md` (24.1–24.21). Excluídos `.zig-cache` e artefatos. O pacote 24_18
estava defasado (sem `examples/`, sem 24.19–24.21 e sem o teste diferencial).

## 2. Documentação e exemplos

- README sincronizado: 82/82, 3 workloads do bench, `MissingStorage`,
  `zig build integration` (Debug e ReleaseFast) e ressalva de consumo
  síncrono do `engine_host`.
- Exemplo do README recompilado e executado (16v/24i/1c); `engine_host`
  executado nos dois modos (40 frames, 960 índices).

## 3. APIs públicas e contratos de memória

- Superfície do `Context`: 43 funções públicas, assinaturas e error sets
  inalterados desde a auditoria 24.8 (única evolução documentada:
  `MissingStorage` na 24.16 e alargamento de `drawDataView` na 24.8).
- Cobertura de doc comments verificada por script: completa onde há contrato
  não-óbvio; ausente só em triviais (`reset`, `pop`, getters). Exceções reais
  encontradas e corrigidas: `beginFrame`/`endFrame` agora documentam a
  máquina de estados. Demais ausências registradas como não-bloqueantes para
  não agitar 10 arquivos às vésperas da RC.
- Contratos de memória rechecados: disjunção em todos os `set*`, validade
  dos slices (tabela do README), sem `Allocator`, sem threads/atomics/locks.

## 4. Limitações conhecidas (inalteradas)

Widgets button/checkbox/sliderFloat; sem texto/fontes; sem clicks/teclado/
unicode, labels longas ou primitivas não-retangulares na temporização;
heap-counter inaplicável por construção; `engine_host` síncrono; sem engine
real; mutação direta de campos do `Context` é violação contratual.

## 5. Checklist de validação final

- [x] `zig version` 0.17.0
- [x] `zig fmt --check build.zig src bench examples` (esta sessão, local)
- [x] `zig build test --summary all` 82/82 Debug (esta sessão, local)
- [x] `zig build test -Doptimize=ReleaseFast` 82/82 (esta sessão, local)
- [x] `zig test src/root.zig` 82/82 (esta sessão, local)
- [x] `zig build integration` Debug + ReleaseFast (local + Fedora do usuário)
- [x] `zig build bench -Doptimize=ReleaseFast`, 12 cenários (local + Fedora)
- [x] Pacote 24_21 verificado por extração limpa: fmt, 82/82, integration, 12 cenários
- [ ] Integração com engine gráfica real (usuário)
- [ ] Bump para 0.2.0 (aguardando autorização)
- [ ] Publicação no GitHub (aguardando autorização)

## 6. Bloqueantes

Nenhum bloqueante técnico encontrado. Restam somente itens com dependência
do usuário (checklist acima). Recomendação: após o OK do usuário nos três
itens, declarar 0.2.0 e publicar.
