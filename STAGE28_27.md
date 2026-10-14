# Etapa 28.27 — Regressão integrada: UTF-8 corrompido antes da interação

## Escopo

Adicionado teste em `src/root.zig` para corrupção externa do armazenamento UTF-8
antes de `Context.inputTextDraggedTracked`. O teste exige rejeição antes de
interação, edição, consumo de eventos ou emissão de geometria.

## Invariantes verificados pelo teste (expectativas, não execução)

- `error.InvalidUtf8` para byte inicial `0xff` no conteúdo do editor.
- Conteúdo, comprimento, cursor, scroll e âncora de arraste preservados.
- Progresso reiniciado (`consumed == 0`, `changes == 0`).
- Nenhum ID registrado, vértice, índice ou comando emitido.
- Frame pode ser encerrado e liberado após a falha.

## Impacto

Apenas teste e documentação. Nenhuma alteração nas APIs públicas, no caminho de
execução, no consumo de memória ou nas dependências. Versão permanece 0.2.0.

## Validação

ZIP submetido à verificação de integridade. Compilação e testes Debug/ReleaseFast
não executados: Zig 0.17.0 indisponível no ambiente. O resultado esperado do
teste ainda precisa ser confirmado por execução real.
