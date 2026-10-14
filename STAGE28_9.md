# Etapa 28.9 — Núcleo de edição UTF-8 sem alocações

## Escopo

Adicionado `src/text_edit.zig`, exportado por `src/root.zig` como `text_edit`. Este é um núcleo de edição de linha única, **não** um widget visual `inputText`.

## Contrato

- `Buffer.init(storage, initial)` recebe armazenamento mutável do chamador e copia texto UTF-8 validado.
- `len` e `cursor` são offsets em **bytes**, sempre em limites de escalares Unicode. Não são índices de grafemas.
- `insertScalar`, `backspace`, `deleteForward`, `moveLeft`, `moveRight` e `setCursor` operam sem heap.
- Inserção verifica capacidade antes de deslocar dados; erros não modificam o texto.
- `init` rejeita origem e destino sobrepostos; o texto inicial não pode conter UTF-8 malformado.
- Campos públicos exigem manutenção dos invariantes pelo chamador; operações validam comprimento, cursor e UTF-8 antes de editar.
- O buffer não insere terminador NUL automaticamente; `view()` retorna apenas bytes válidos.

## Limitações deliberadas

- Sem seleção, IME, composição, grapheme clusters, normalização, histórico de undo/redo ou layout visual.
- Movimentação por **pontos de código**, não por grafemas; sequências com combining marks podem exigir comportamento visual adicional.
- `check()` valida o conteúdo inteiro a cada operação: O(n), priorizando segurança neste marco. A otimização requer testes e benchmarks.
- A integração com eventos da engine e com foco de widgets será implementada posteriormente, após validar este contrato.

## Validação

Foram escritos três testes cobrindo UTF-8 de 1 a 4 bytes, capacidade, cursores inválidos e operações de edição. Não foram executados: Zig 0.17.0 não está disponível no ambiente. Não afirmar compilação ou compatibilidade sem validação.

## Arquivos

- Criado: `src/text_edit.zig`.
- Modificado: `src/root.zig` (export e inclusão dos testes).
- Criado: `STAGE28_9.md`.

Versão mantida em 0.2.0. Nenhuma alteração remota.
