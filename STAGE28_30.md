# NitroUI — Etapa 28.30: auditoria de retomada após perda de foco

## Escopo

Adicionados dois testes de regressão em `src/text_input.zig`, sem alterar APIs ou implementação de runtime.

1. `stage28_30 focus loss clears Shift before a failing insertion`: pressiona Shift, perde e recupera foco, falha por capacidade na inserção, verifica `Progress` e retoma o sufixo sem o evento que falhou. A navegação retomada não pode selecionar texto por causa de um Shift obsoleto.
2. `stage28_30 ignored events count as consumed and reset stale progress`: eventos ignorados sem foco ainda contam como consumidos; um lote vazio reinicializa corretamente um objeto `Progress` reutilizado.

## Contratos

- A engine fornece eventos ordenados e decide se descarta ou tenta novamente o evento que falhou.
- `Progress` contabiliza eventos do lote atual, incluindo eventos ignorados, e conserva estados de modificadores e foco após o prefixo consumido.
- A falha da inserção individual é atômica; operações anteriores do lote não são revertidas.
- Não há novas alocações, buffers, dependências ou alterações de ABI/API.

## Validação

- Revisão estática do código e da configuração `build.zig` realizada.
- Compilador Zig 0.17.0 não encontrado no ambiente; testes Debug/ReleaseFast, integração e benchmarks **não executados**.
- Testes são expectativas de regressão, não resultados confirmados.
