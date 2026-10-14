# Etapa 28.28 — Regressão de progresso com Shift e recuperação

## Escopo

Adicionado teste unitário em `src/text_input.zig` para falha de inserção
UTF-8 multibyte após seleção por Shift, seguida de retomada apenas do sufixo
não consumido. Não há alterações de API nem de implementação em runtime.

## Contratos testados (expectativas; teste ainda não executado)

- Evento Shift-down e movimento à esquerda são contabilizados como consumidos.
- Inserção de quatro bytes em buffer de três bytes falha atomicamente.
- `Progress` informa prefixo consumido, zero alterações e Shift/foco atuais.
- Conteúdo, cursor e seleção permanecem coerentes após a falha.
- A engine descarta explicitamente o evento falho; Shift-up e movimento
  restantes são processados sem repetir os eventos anteriores.
- `Progress` previamente preenchido é reinicializado no começo da chamada.

## Auditoria de build

O `build.zig` existente declara `test`, `integration` e `bench`, com módulo
`nitro_ui` e exemplo de consumidor headless. `build.zig.zon` declara Zig mínimo
0.17.0 e nenhuma dependência externa. A presença dessas etapas não significa
que tenham sido executadas ou estejam corretas.

## Validação

- Verificação estática do teste e da estrutura de build: realizada.
- Integridade do ZIP: verificada.
- Compilação Zig 0.17.0, testes Debug/ReleaseFast, integração e benchmark:
  **não executados**, compilador indisponível neste ambiente.
- Versão: 0.2.0, inalterada.
