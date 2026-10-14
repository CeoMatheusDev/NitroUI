# NitroUI — Etapa 28.29: atomicidade de inserções Unicode com seleção

## Escopo

Adicionados dois testes de regressão em `src/text_input.zig`, sem mudanças no runtime ou em APIs públicas.

1. Substituição de seleção por escalar UTF-8 de quatro bytes quando o armazenamento é insuficiente: o evento falha atomicamente, preserva bytes, cursor e seleção, e `Progress` reporta apenas o prefixo consumido. O teste retoma somente os eventos pendentes após descartar explicitamente o evento falho.
2. Escalar Unicode inválido (surrogate `0xD800`) após movimentação de cursor: verifica `InvalidScalar`, ausência de mutação pela inserção falha e retomada sem replay do prefixo.

## Contratos

- O editor e os buffers continuam pertencendo à aplicação.
- Eventos anteriores ao erro podem ter efeitos; o evento de inserção que falhou deve ser atômico.
- A aplicação decide descartar ou reprocessar o evento falho e deve fornecer o estado de modificadores/foco reportado.
- Não há novas alocações, dependências ou estado persistente.
- Versão mantida em 0.2.0.

## Validação

Os testes foram **escritos, não executados**. O compilador Zig 0.17.0 não estava disponível. O ZIP foi verificado quanto à integridade, não quanto à compilação. Integração e benchmarks permanecem pendentes.
