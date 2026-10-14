# NitroUI — Etapa 28.61

## Escopo

Adicionado teste determinístico em `src/text_edit.zig` que percorre todas as 1.024 sequências de cinco operações (esquerda, direita, backspace e delete-forward) sobre `a€🚀b`. Um modelo independente acompanha os comprimentos em bytes de cada scalar e o cursor em índices de scalar, permitindo verificar os offsets UTF-8 produzidos pela implementação após cada operação (5.120 passos especificados).

## Contratos

- Armazenamento fixo pertencente ao chamador, sem heap.
- Navegação e exclusão somente em limites de scalar UTF-8.
- Cursor, comprimento e ausência de seleção verificados a cada passo.
- API pública e implementação de produção inalteradas.
- Versão 0.2.0 preservada.

## Validação

A execução com Zig 0.17.0 permanece pendente enquanto o compilador não estiver disponível. O autoteste Shell com Zig simulado valida apenas o script de CI, não o código Zig. Nenhum benchmark realizado.
