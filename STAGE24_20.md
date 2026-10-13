# Etapa 24.20 — Contrato de integração do lado da engine

Versão permanece 0.1.0. Nenhuma alteração em `src/` ou APIs públicas.

## Escopo

Criado `examples/engine_host.zig`: um consumidor headless **externo ao módulo**
que importa somente `nitro_ui`, simula a engine fornecendo tempo, input,
buffers e um renderer síncrono, e executa 40 frames completos.

Verificações do renderer: contagens exatas (16 vértices, 24 índices,
1 comando por frame), cobertura contínua dos índices, referências de
vértices válidas, clip e texture handle, ciclo `ready` → consumo →
`releaseFrame()` → `idle`, reutilização dos buffers e 960 índices totais.

O teste é independente do backend, sem GPU, sem dependências externas e
sem alocação por widget. **Não é integração com uma engine real** e não
comprova comportamento de submissão assíncrona à GPU.

## Build

```sh
zig build integration
zig build integration -Doptimize=ReleaseFast
```

O `build.zig` injeta o módulo `nitro_ui`; `build.zig.zon` inclui `examples`.

## Validação

Alterações inspecionadas estaticamente. Compilação e execução Zig 0.17.0
**não realizadas neste ambiente**. A baseline externa informada permanece
82/82 testes Debug e ReleaseFast da Etapa 24.19.

## Próximo passo

Integrar o módulo a uma engine Zig real, testar o contrato de consumo de
buffers no renderer real, validar Debug/ReleaseFast e obter autorização
explícita antes de alterar versão ou publicar no GitHub.

## Verificação posterior (sessão de continuidade, Zig 0.17.0)

- Inspecionado `examples/engine_host.zig` na íntegra: somente API pública,
  consumo síncrono antes de `releaseFrame()`, checagens de contagens/clip/
  textura/índices e 40×24 = 960 índices totais. Nenhum defeito encontrado.
- `zig fmt --check` (incl. `examples`), `zig build integration` Debug e
  ReleaseFast, suíte 82/82 e bench: tudo aprovado localmente, consistente
  com a validação Fedora informada pelo usuário (82/82, 12 cenários).
- `build.zig.zon` inclui `examples` nos paths; `build.zig` expõe o step
  `integration` sem instalar artefatos. Trabalho das etapas 24.8–24.19
  confirmado intacto no workspace.
