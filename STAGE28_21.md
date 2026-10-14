# Etapa 28.21 — Pré-validação do editor antes da interação

## Escopo

Adicionada `text_edit.Buffer.validateState()` para validação pública, sem mutação, do armazenamento UTF-8, cursor e âncora. `Context.inputTextDraggedInternal()` passa a validar esse estado e o deslocamento horizontal antes de registrar a interação do widget.

## Justificativa

Antes, um editor externamente corrompido podia ser detectado somente durante a edição ou após a interação, deixando o checkpoint de interação responsável por desfazer estado. A validação antecipada evita esse percurso para erros conhecidos e não copia o texto.

## Contratos

- Não modifica conteúdo, cursor, âncora ou scroll em caso de falha de pré-validação.
- Não introduz alocações, buffers ou dependências.
- Mantém APIs existentes e adiciona somente um método de inspeção.
- Custo de validação O(n) pelo percurso UTF-8.

## Validação

Teste de regressão escrito para âncora inválida e UTF-8 corrompido externamente. **Compilação e testes Zig 0.17.0 não executados**: compilador indisponível. A transação entre edição de eventos e falha posterior de renderização continua pendente; esta etapa não a resolve.
