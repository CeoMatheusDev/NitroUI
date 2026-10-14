# Etapa 28.63 — Oráculo de substituição UTF-8 com seleção

Adicionado teste determinístico em `src/text_edit.zig` para todas as 25 combinações de limites de seleção (incluindo seleção invertida e vazia) em `a€🚀b`, com três escalares de comprimentos distintos (1, 3 e 4 bytes): 75 casos.

O oráculo constrói os bytes esperados independentemente da rotina de edição, verifica comprimento, cursor, ausência de seleção e validade UTF-8. Nos casos sem capacidade suficiente, compara todos os bytes do armazenamento e confirma preservação de cursor, âncora e comprimento.

Sem mudanças de API pública, runtime, dependências ou versão (0.2.0). Compilação/testes Zig exigem Zig 0.17.0 real; autotestes Shell usam compilador simulado e não validam código Zig.
