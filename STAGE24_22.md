# Etapa 24.22 — Release 0.2.0 e publicação no GitHub

Versão: **0.2.0** (bump autorizado pelo usuário nesta etapa).

## Bump

- `build.zig.zon`: `.version = "0.2.0"` (fingerprint inalterado).
- `README.md`: versão e seção de limitações atualizadas.
- Comentário histórico em `src/draw.zig` ("compatibilidade em 0.1.0")
  preservado como está: fato histórico, sem implicação de comportamento.

## Publicação (autorizada pelo usuário nesta etapa)

- Repo `CeoMatheusDev/NitroUI` já existia com 1 commit (conteúdo antigo,
  "milestone 3"). Estratégia: clone + commit da árvore 0.2.0 por fast-forward,
  sem force-push e sem destruir histórico.
- Publicados: `build.zig`, `build.zig.zon`, `src/`, `bench/`, `examples/`,
  `README.md`, `STAGE*.md`. Tag `v0.2.0` criada e enviada.
- Não publicados: `.zig-cache/`, `zig-out/`, ZIPs de milestone (fora da árvore).

## Ressalva registrada no ato

Release 0.2.0 declarada com a limitação conhecida e documentada de ausência
de integração com engine real (padrão documentado + harness headless apenas).
Nenhum commit, tag ou push afirmado sem execução real — ver comandos abaixo.

## Validação pré-push (Zig 0.17.0)

```sh
zig fmt --check build.zig src bench examples
zig build test --summary all          # Debug
zig build test -Doptimize=ReleaseFast --summary all
zig test src/root.zig
zig build integration                 # Debug + ReleaseFast
zig build bench -Doptimize=ReleaseFast
```
