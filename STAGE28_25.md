# Etapa 28.25 — Auditoria de pré-validação e teste de regressão

## Escopo

Foi acrescentado um teste integrado para `Context.inputTextDraggedTracked` que
injeta um deslocamento horizontal inválido (`-1`) antes do processamento de
interação, edição e renderização.

## Invariantes verificados pelo teste (expectativas; ainda não executado)

- Retorno `error.InvalidPosition`.
- Nenhum evento de texto consumido e nenhuma alteração aplicada.
- `Progress` reinicializado com o estado inicial de Shift e foco `false`.
- Texto, cursor, âncora de arraste e deslocamento horizontal preservados.
- Nenhum ID registrado e nenhum vértice, índice ou comando emitido.
- Contexto ainda pode encerrar e liberar o frame.

## Compatibilidade e memória

Nenhuma API pública, estrutura, dependência ou política de ownership foi alterada.
Nenhuma alocação adicional no hot path. A versão permanece 0.2.0.

## Validação

A integridade do arquivo ZIP foi verificada separadamente. O compilador Zig
0.17.0 não está disponível no ambiente: compilação, testes Debug/ReleaseFast,
integração e benchmarks **não foram executados**. O teste não deve ser
considerado aprovado até execução real.

## Pendências

- Validar o projeto completo com Zig 0.17.0.
- Revisar a semântica de `drag_anchor` quando a renderização falha após captura.
- Integrar com engine real e medir custos.
