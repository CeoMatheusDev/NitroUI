# Etapa 24.6 — Regressões de integração

Versão mantida: 0.1.0.

## Escopo

Dois testes headless em `src/root.zig` verificam:

1. Falha de geometria em checkbox, rollback de contadores e IDs de diagnóstico,
   seguida de reutilização do mesmo ID em um widget bem-sucedido no mesmo frame.
2. Estabilidade da view de renderização durante `ready`, rejeição de operações
   de construção nesse estado e reset lógico da geometria no frame seguinte.

Nenhuma API pública ou módulo de produção foi modificado.

## Limites

Não mede latência, alocações, nem segurança contra mutação por aliases externos.
A validade dos slices continua sendo obrigação contratual da engine.

## Validação pendente no Fedora (Zig 0.17.0)

```sh
zig fmt build.zig src bench
zig fmt --check build.zig src bench
zig build test --summary all
zig test src/root.zig
zig build bench -Doptimize=ReleaseFast
```

Baseline anterior informada pelo usuário: 69/69 testes. Esperados 71 testes,
caso ambos sejam descobertos. Nenhuma execução local foi realizada.
