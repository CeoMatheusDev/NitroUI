# Etapa 24.13 — Validação consolidada pré-0.2.0

Versão mantida: 0.1.0. Correção de 1 bug real de teste; nenhuma API alterada.

## Achado: teste ambiente-dependente exposto pelo modo ReleaseFast

`zig build test -Doptimize=ReleaseFast` resultou em 78/79: o teste
`memory.test.aligned reservation rejects overflow without mutation` esperava
`error.SizeOverflow` para `reserveAligned(maxInt(usize), 8)`, mas obteve
`error.OutOfCapacity`.

Causa: com `used == 0`, o overflow só ocorre se o padding de alinhamento for
não-zero, o que depende do endereço do array no stack. Em Debug o endereço
era desalinhado mod 8 (padding > 0 → `SizeOverflow`); em ReleaseFast o layout
do stack alinhou a 8 (padding = 0 → `0 + maxInt` não estoura → `OutOfCapacity`).
O código da arena está correto nos dois casos (falha sem mutação, `used == 0`
preservado); a expectativa do teste é que era inválida.

Correção (`src/memory.zig`): o teste escolhe deterministicamente entre
`storage[0..]` e `storage[1..]` (endereços A e A+1 mod 8 nunca são ambos zero),
garantindo padding não-zero e portanto `SizeOverflow` em qualquer build.
Auditei os demais testes de overflow/capacidade: todos os outros têm resultado
independente de alinhamento. Após a correção: 79/79 em Debug e ReleaseFast.

## Validação consolidada executada (Zig 0.17.0, Fedora)

```sh
zig fmt --check build.zig src bench            # limpo
zig build test --summary all                   # 79/79 (Debug)
zig build test -Doptimize=ReleaseFast --summary all  # 79/79
zig test src/root.zig                          # 79/79
zig build bench -Doptimize=ReleaseFast         # 12 linhas, checksums e
                                               # ns_widget_med estáveis
```

Restrições estruturais verificadas por inspeção: zero ocorrências de
`Allocator` em `src/`; zero threads/atomics/locks em `src/` e `bench/`
("atomic" aparece só no sentido transacional em nomes de teste e docs).

## Matriz de readiness 0.2.0 (critérios §24)

| Critério | Estado | Evidência |
|---|---|---|
| Testes unitários/integração/regressão | Demonstrado | 79/79 Debug + ReleaseFast |
| Capacidade/overflow/underflow tratados | Demonstrado | auditoria 24.8 + correção acima |
| Ownership e ciclo de vida dos slices | Demonstrado/documentado | README + STAGE24_8 |
| APIs coerentes, contratos explícitos | Demonstrado | sem mudanças silenciosas desde 24.1 |
| Buffers reutilizados, sem alloc por widget | Demonstrado | sem `Allocator`; bench só com buffers fixos |
| Zero allocs pós-warm-up verificada | **Pendente** | estrutural, sem contador experimental |
| Benchmark reproduzível + temporal | Demonstrado | rect/widget/idstr, O(n), 2+ runs |
| Escalabilidade sem regressão | Demonstrado | ns/widget constante em 64–4096 |
| Uso como módulo local Zig | Parcial | padrão documentado + exemplo compilado; sem engine real |
| Independência de backend/SO, sem deps externas | Demonstrado | `build.zig.zon` sem dependências; sem headers C/ABI C |
| Documentação (integração, contratos, exemplo, comandos) | Demonstrado | README + exemplo verificado |

## Conclusão

**0.2.0 ainda não liberada.** Pendências antes da liberação: verificação de
alocações por contador/experimento, integração contra um engine real,
autorização explícita para o bump de versão e para a publicação no GitHub
(vedada até lá). Nenhum commit, tag ou release foi criado ou afirmado.
