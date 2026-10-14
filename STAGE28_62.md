# Etapa 28.62 — Oráculo independente de conteúdo UTF-8

- Adicionado teste determinístico de 256 sequências de quatro operações (1.024 estados intermediários) em `src/text_edit.zig`.
- Operações: inserir U+1F680, mover à esquerda, Backspace e Delete.
- Modelo de referência mantém Unicode scalars independentes dos offsets em bytes do editor e reconstrói o conteúdo UTF-8 esperado a cada operação.
- Confere bytes completos, cursor, seleção e invariantes UTF-8. Complementa a etapa 28.61, que verificava apenas larguras e offsets.
- Não há alteração de runtime, API pública, dependências ou alocações no hot path.
- Compilação e execução Zig 0.17.0 pendentes se o compilador não estiver instalado.
