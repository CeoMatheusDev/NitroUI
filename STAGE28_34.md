# Etapa 28.34 — Pré-validação e progresso diante de cursor inválido

## Escopo

Adicionado teste de regressão em `src/text_input.zig` para o caso em que a aplicação viola o invariante público do cursor entre frames. O lote contém um evento de foco válido, um evento de navegação que deve falhar e uma inserção que não pode ser executada.

## Contrato esperado

- `applyTracked` retorna `error.InvalidCursor` no evento de navegação.
- `Progress.consumed == 1`: somente o evento de foco foi consumido.
- `Progress.changes == 0`; estado de foco e Shift correspondem ao prefixo consumido.
- O texto e o cursor inválido permanecem inalterados; o evento Unicode posterior não é processado.
- Nenhuma mudança em API pública, runtime, dependências ou versão (0.2.0).

## Validação

A integridade do pacote e a auditoria estrutural podem ser verificadas sem Zig. **A compilação e a execução do teste ainda dependem do Zig 0.17.0**. Em um ambiente com esse compilador:

```sh
zig version
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseFast
zig build integration -Doptimize=Debug
zig build bench -Doptimize=ReleaseFast
```

Não interpretar a presença de testes como aprovação. O código não foi compilado neste ambiente.
