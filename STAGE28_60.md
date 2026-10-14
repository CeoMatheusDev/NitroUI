# NitroUI — Etapa 28.60

## Escopo

Adicionado teste determinístico de equivalência entre o editor e um modelo ASCII independente, com armazenamento fixo e sem alocador. Enumera todas as 3.125 sequências de cinco operações dentre inserir `X`, mover à esquerda, mover à direita, backspace e delete-forward, começando com `ab`. Confere conteúdo, comprimento, cursor, ausência de seleção e invariantes após cada operação (15.625 verificações de estado).

Nenhuma API ou código de produção alterado. Versão permanece 0.2.0.

## Limites

O modelo exercita apenas ASCII e não substitui testes de Unicode, seleções, falhas de capacidade ou execução real com Zig 0.17.0. A execução com Zig depende da disponibilidade do compilador exato.
